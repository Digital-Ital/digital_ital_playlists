module MusicMetadata
  class TrackDossierRefreshService
    REFRESH_BUDGET_SECONDS = 22
    REFRESH_STALE_AFTER = 2.minutes

    class RefreshInProgress < StandardError; end

    def initialize(track)
      @track = track
    end

    def call
      @enrichment = TrackEnrichment.find_or_create_by!(track: @track)
      claim_refresh_slot!

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REFRESH_BUDGET_SECONDS
      spotify_result = SpotifySource.new(@track, deadline: deadline).call
      spotify_metadata = spotify_result.metadata.to_h
      isrc = spotify_metadata[:isrc] || spotify_metadata["isrc"]
      spotify_album = spotify_metadata[:album] || spotify_metadata["album"]
      musicbrainz_result = MusicBrainzSource.new(
        @track,
        isrc: isrc,
        spotify_album: spotify_album,
        deadline: deadline
      ).call
      discogs_result = discogs_source_result(deadline, spotify_album: spotify_album)
      wikipedia_result = WikipediaSongContextSource.new(@track, deadline: deadline).call
      results = [ spotify_result, musicbrainz_result, discogs_result, wikipedia_result ]

      @enrichment.with_lock do
        results.each { |result| sync_source_result!(result) }
        errors = results.filter_map(&:error)

        @enrichment.update!(
          status: resulting_status(errors),
          last_refreshed_at: Time.current,
          last_error: errors.presence&.join(" | ")
        )
      end

      @enrichment
    rescue RefreshInProgress
      @enrichment
    rescue StandardError => e
      Rails.logger.warn("Track dossier refresh failed for #{@track.id}: #{e.message}")
      @enrichment ||= TrackEnrichment.find_or_create_by!(track: @track)
      @enrichment.with_lock do
        @enrichment.update!(status: "error", last_attempted_at: Time.current, last_error: e.message)
      end
      @enrichment
    end

    private

    def claim_refresh_slot!
      @enrichment.with_lock do
        if @enrichment.status == "refreshing" &&
            @enrichment.last_attempted_at.present? &&
            @enrichment.last_attempted_at > REFRESH_STALE_AFTER.ago
          raise RefreshInProgress
        end

        @enrichment.expire_temporary_claims!
        @enrichment.update!(status: "refreshing", last_attempted_at: Time.current, last_error: nil)
      end
    end

    def discogs_source_result(deadline, spotify_album:)
      if @enrichment.discogs_release_id.present?
        DiscogsSource.new(@track, @enrichment, deadline: deadline).call
      else
        DiscogsCandidateSource.new(@track, spotify_album: spotify_album, deadline: deadline).call
      end
    end

    def sync_source_result!(result)
      return unless result.successful?

      TrackMetadataClaim.transaction do
        @enrichment.track_metadata_claims.where(source: result.source).delete_all
        Array(result.claims).each do |claim|
          @enrichment.track_metadata_claims.create!(
            claim.merge(
              source: result.source,
              fetched_at: Time.current
            )
          )
        end
      end
    end

    def resulting_status(errors)
      return "ready" if @enrichment.active_claims.exists?
      return "error" if errors.any?

      "pending"
    end
  end
end
