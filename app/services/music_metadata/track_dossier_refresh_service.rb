module MusicMetadata
  class TrackDossierRefreshService
    def initialize(track)
      @track = track
    end

    def call
      @enrichment = TrackEnrichment.find_or_create_by!(track: @track)

      @enrichment.with_lock do
        @enrichment.expire_temporary_claims!
        @enrichment.update!(status: "refreshing", last_attempted_at: Time.current, last_error: nil)

        spotify_result = SpotifySource.new(@track).call
        isrc = spotify_result.metadata.to_h[:isrc] || spotify_result.metadata.to_h["isrc"]
        musicbrainz_result = MusicBrainzSource.new(@track, isrc: isrc).call
        discogs_result = DiscogsSource.new(@track, @enrichment).call
        results = [ spotify_result, musicbrainz_result, discogs_result ]

        results.each { |result| sync_source_result!(result) }
        errors = results.filter_map(&:error)

        @enrichment.update!(
          status: resulting_status(errors),
          last_refreshed_at: Time.current,
          last_error: errors.presence&.join(" | ")
        )
      end

      @enrichment
    rescue StandardError => e
      Rails.logger.warn("Track dossier refresh failed for #{@track.id}: #{e.message}")
      @enrichment ||= TrackEnrichment.find_or_create_by!(track: @track)
      @enrichment.update!(status: "error", last_attempted_at: Time.current, last_error: e.message)
      @enrichment
    end

    private

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
