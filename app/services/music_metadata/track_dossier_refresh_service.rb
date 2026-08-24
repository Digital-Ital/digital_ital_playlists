module MusicMetadata
  class TrackDossierRefreshService
    REFRESH_BUDGET_SECONDS = 22
    # Spotify is quick but has two HTTP calls. MusicBrainz is allowed enough
    # room for its paced safe lookup, while a hard reserve ensures Discogs can
    # still complete independently if MusicBrainz is slow or unavailable.
    SPOTIFY_MAX_SECONDS = 5.0
    MUSICBRAINZ_MAX_SECONDS = 9.0
    DISCOGS_RESERVED_SECONDS = 9.0
    DISCOGS_ERROR_RETRY_AFTER = 10.minutes
    DISCOGS_NO_MATCH_RETRY_AFTER = 1.hour
    REFRESH_STALE_AFTER = 2.minutes

    class RefreshInProgress < StandardError; end

    def initialize(track)
      @track = track
    end

    def call
      @enrichment = TrackEnrichment.find_or_create_by!(track: @track)
      claim_refresh_slot!

      global_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REFRESH_BUDGET_SECONDS
      spotify_result = SpotifySource.new(
        @track,
        deadline: source_deadline(global_deadline, SPOTIFY_MAX_SECONDS)
      ).call
      spotify_metadata = spotify_result.metadata.to_h
      isrc = spotify_metadata[:isrc] || spotify_metadata["isrc"]
      spotify_album = spotify_metadata[:album] || spotify_metadata["album"]
      musicbrainz_result = MusicBrainzSource.new(
        @track,
        isrc: isrc,
        spotify_album: spotify_album,
        deadline: musicbrainz_deadline(global_deadline)
      ).call

      # Discogs keeps the original global deadline. The MusicBrainz child
      # deadline above leaves it at least DISCOGS_RESERVED_SECONDS whenever
      # Spotify has completed within its own bounded phase.
      discogs_result = discogs_source_result(global_deadline, spotify_album: spotify_album)
      # Context is optional, so it only uses time left after the three primary
      # sources rather than stealing time from Discogs.
      wikipedia_result = WikipediaSongContextSource.new(@track, deadline: global_deadline).call
      results = [ spotify_result, musicbrainz_result, discogs_result, wikipedia_result ]

      @enrichment.with_lock do
        results.each { |result| sync_source_result!(result) }
        errors = results.filter_map(&:error)

        checked_at = Time.current
        refresh_attributes = {
          status: resulting_status(errors),
          last_error: errors.presence&.join(" | "),
          discogs_refresh: discogs_refresh_attributes(discogs_result, checked_at)
        }
        # A partial refresh can update other sources while preserving older
        # MusicBrainz claims after a transient error. Only mark the dossier
        # fully refreshed when every source completed successfully.
        refresh_attributes[:last_refreshed_at] = Time.current if errors.empty?
        @enrichment.update!(refresh_attributes)
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

    def source_deadline(global_deadline, max_seconds)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [ global_deadline, now + max_seconds ].min
    end

    def musicbrainz_deadline(global_deadline)
      [
        source_deadline(global_deadline, MUSICBRAINZ_MAX_SECONDS),
        global_deadline - DISCOGS_RESERVED_SECONDS
      ].min
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

    # This is operational state rather than provider metadata. It gives the
    # Listening Desk an honest Discogs outcome even when a safe lookup returns
    # zero claims, when configuration is missing, or when an error preserves
    # older temporary claims.
    def discogs_refresh_attributes(result, checked_at)
      metadata = result.metadata.to_h.stringify_keys
      outcome = metadata["outcome"].presence || inferred_discogs_outcome(result)
      state = {
        "mode" => metadata["mode"].presence || (result.source == "discogs" ? "curator_selected" : "automatic_candidate"),
        "outcome" => outcome,
        "checked_at" => checked_at.iso8601
      }
      state["reason"] = metadata["reason"] if metadata["reason"].present?

      case outcome
      when "found"
        expires_at = discogs_claims_expires_at(result)
        state["claims_expires_at"] = expires_at.iso8601 if expires_at.present?
      when "no_safe_candidate"
        state["next_retry_at"] = (checked_at + DISCOGS_NO_MATCH_RETRY_AFTER).iso8601
      when "error"
        state["error_kind"] = discogs_error_kind(result.error)
        state["next_retry_at"] = (checked_at + DISCOGS_ERROR_RETRY_AFTER).iso8601
      when "selected_release_mismatch"
        state["error_kind"] = "selected_release_mismatch"
      end

      state
    end

    def inferred_discogs_outcome(result)
      return "skipped" if result.skipped?
      return "error" if result.error.present?
      return "found" if Array(result.claims).any?

      "no_safe_candidate"
    end

    def discogs_claims_expires_at(result)
      Array(result.claims).filter_map do |claim|
        claim[:expires_at] || claim["expires_at"]
      end.max
    end

    def discogs_error_kind(error)
      case error.to_s
      when /rate limited/i then "rate_limited"
      when /network error|Net::(?:Open|Read)Timeout/i then "network"
      when /refresh time budget exhausted/i then "deadline"
      else "unknown"
      end
    end

    def resulting_status(errors)
      return "ready" if @enrichment.active_claims.exists?
      return "error" if errors.any?

      "pending"
    end
  end
end
