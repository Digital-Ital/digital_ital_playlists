class ListeningController < ApplicationController
  AUTO_REFRESH_AFTER = 30.days
  AUTO_RETRY_AFTER = 1.hour
  DISCOGS_REFRESH_AFTER = 6.hours

  def show
    @query = params[:q].to_s.strip
    @search_results = Spotify::CrateLookup.search(@query) if @query.present?

    @spotify = Spotify::ListeningService.new
    @connected = @spotify.connected?

    if @connected
      @current_track = cached_current_track
      @recent_tracks = cached_recent_tracks
    else
      @recent_tracks = []
    end

    @selected_lookup = selected_lookup
    @dossier_track = selected_dossier_track
    @dossier_enrichment = @dossier_track&.track_enrichment
    @dossier_claims = @dossier_enrichment&.active_claims&.to_a || []
  rescue Spotify::ListeningService::ConfigurationError, Spotify::ListeningService::ApiError => e
    Rails.logger.warn "Listening Desk unavailable: #{e.message}"
    @listening_error = e.message
    @recent_tracks ||= []
  end

  def footprint
    @scope = params[:scope].to_s
    return head :bad_request unless %w[artist album].include?(@scope)

    source = requested_track
    return head :bad_request if source.blank?

    @footprint = Spotify::CrateLookup.footprint_for(source, scope: @scope)
    @footprint_key = params[:key].to_s.presence || "lookup"

    render partial: "footprint", locals: {
      footprint: @footprint,
      scope: @scope,
      footprint_key: @footprint_key
    }
  end

  def dossier
    track = Track.find_by(id: params[:track_id])
    return head :not_found unless track

    enrichment = track.track_enrichment
    enrichment&.expire_temporary_claims!

    render partial: "dossier_content", locals: { track: track, enrichment: enrichment }
  end

  # Called automatically by the Listening Desk for the exact song currently
  # playing. It is intentionally unavailable for arbitrary catalogue records.
  def auto_dossier
    track = Track.find_by(id: params[:track_id])
    return head :not_found unless track
    return head :unprocessable_entity unless current_track_matches?(track)

    enrichment = track.track_enrichment
    enrichment = MusicMetadata::TrackDossierRefreshService.new(track).call if auto_refresh_needed?(enrichment)
    enrichment ||= TrackEnrichment.find_or_create_by!(track: track)

    render partial: "curator_summary", locals: {
      track: track,
      enrichment: enrichment,
      claims: enrichment.active_claims.to_a
    }
  end

  private

  def cached_current_track
    Rails.cache.fetch("listening-desk/current-track", expires_in: 20.seconds) do
      @spotify.currently_playing
    end
  end

  def cached_recent_tracks
    Rails.cache.fetch("listening-desk/recent-tracks", expires_in: 60.seconds) do
      @spotify.recently_played(limit: 10)
    end
  end

  def current_track_matches?(track)
    current_track = Rails.cache.read("listening-desk/current-track")
    current_track.to_h.symbolize_keys[:spotify_id] == track.spotify_id
  end

  def auto_refresh_needed?(enrichment)
    return true if enrichment.blank?
    return false if enrichment.status == "refreshing" &&
      enrichment.last_attempted_at.present? &&
      enrichment.last_attempted_at > MusicMetadata::TrackDossierRefreshService::REFRESH_STALE_AFTER.ago
    return false if enrichment.last_attempted_at.present? && enrichment.last_attempted_at > AUTO_RETRY_AFTER.ago

    claims = enrichment.active_claims
    discogs_missing = claims.where(source: [ "discogs", "discogs_candidate" ]).none?

    enrichment.last_refreshed_at.blank? ||
      enrichment.last_refreshed_at < AUTO_REFRESH_AFTER.ago ||
      (discogs_missing && enrichment.last_attempted_at < DISCOGS_REFRESH_AFTER.ago)
  end

  def selected_lookup
    if params[:track_id].present?
      track = Track.find_by(id: params[:track_id])
      return Spotify::CrateLookup.from_local_track(track) if track
    end

    selected_track = requested_track || @current_track
    Spotify::CrateLookup.from_spotify(selected_track) if selected_track.present?
  end

  def selected_dossier_track
    return Track.find_by(id: params[:track_id]) if params[:track_id].present?
    return unless @selected_lookup&.fetch(:match_type, nil) == :exact

    spotify_id = @selected_lookup.dig(:source, :spotify_id)
    Track.find_by(spotify_id: spotify_id)
  end

  def requested_track
    return unless params[:spotify_id].present? || params[:name].present?

    {
      spotify_id: params[:spotify_id],
      name: params[:name],
      artist: params[:artist],
      album: params[:album],
      image_url: params[:image_url],
      external_url: params[:external_url],
      duration_ms: params[:duration_ms]
    }
  end
end
