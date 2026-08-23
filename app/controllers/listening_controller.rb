class ListeningController < ApplicationController
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

  def selected_lookup
    if params[:track_id].present?
      track = Track.find_by(id: params[:track_id])
      return Spotify::CrateLookup.from_local_track(track) if track
    end

    selected_track = requested_track || @current_track
    Spotify::CrateLookup.from_spotify(selected_track) if selected_track.present?
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
