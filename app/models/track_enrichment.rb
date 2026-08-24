class TrackEnrichment < ApplicationRecord
  DISPLAY_FIELD_ORDER = %w[
    isrc
    release_date
    release_country
    release_title
    release_type
    release_format
    release_position
    release_track_count
    content_advisory
    label
    catalogue_number
    recording_note
    recording_location
    work_title
    work_type
    work_disambiguation
    iswc
    producer
    engineer
    mastering_engineer
    mixer
    performer
    writer
    composer
    lyricist
    arranger
    relationship_fact
    song_context
    genre
    tag
  ].freeze

  MULTI_VALUE_FIELDS = %w[
    release_format
    label
    catalogue_number
    recording_location
    iswc
    producer
    engineer
    mastering_engineer
    mixer
    performer
    writer
    composer
    lyricist
    arranger
    relationship_fact
    genre
    tag
  ].freeze

  SUMMARY_CLASSIFICATION_FIELDS = %w[genre tag].freeze
  SUMMARY_SIGNAL_FIELDS = %w[
    release_type
    release_format
    release_position
    release_track_count
    content_advisory
    recording_note
    recording_location
    work_title
    work_type
    work_disambiguation
    iswc
    producer
    engineer
    mastering_engineer
    mixer
    performer
    writer
    composer
    lyricist
    arranger
    relationship_fact
  ].freeze
  SUMMARY_SOURCE_ORDER = %w[spotify musicbrainz discogs discogs_candidate wikipedia].freeze
  SUMMARY_CLASSIFICATIONS_PER_SOURCE_LIMIT = 8
  SUMMARY_SIGNALS_PER_SOURCE_LIMIT = 6
  SUMMARY_SIGNAL_LIMIT = 12

  belongs_to :track
  has_many :track_metadata_claims, dependent: :destroy

  validates :status, presence: true

  def active_claims
    track_metadata_claims.where("expires_at IS NULL OR expires_at > ?", Time.current)
  end

  def expire_temporary_claims!
    # Discogs data is temporary under its API terms; this includes automatic
    # candidates as well as curator-selected Discogs release claims.
    track_metadata_claims.where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
                         .delete_all
  end

  def discogs_lookup_state
    state = discogs_refresh
    return {} unless state.is_a?(Hash)

    state.stringify_keys
  end

  def discogs_candidate_strategy_stale?
    state = discogs_lookup_state
    return true if state["mode"] == "automatic_candidate" &&
      state["candidate_strategy"] != MusicMetadata::DiscogsCandidateSource::CANDIDATE_STRATEGY

    candidate_claims = active_claims.where(source: "discogs_candidate").to_a
    return false if candidate_claims.empty?

    candidate_claims.none? do |claim|
      claim.value.to_h["candidate_strategy"] == MusicMetadata::DiscogsCandidateSource::CANDIDATE_STRATEGY
    end
  end

  def discogs_release_id
    decisions["discogs_release_id"].presence
  end

  def set_discogs_release_id!(value)
    new_value = value.to_s.strip.presence
    return if new_value == discogs_release_id

    transaction do
      updated_decisions = decisions
      if new_value.present?
        updated_decisions["discogs_release_id"] = new_value
      else
        updated_decisions.delete("discogs_release_id")
      end

      # A curator release change invalidates both its temporary claims and the
      # operational result that described the previous release. Clearing the
      # attempt timestamp lets the newly chosen release be checked immediately.
      update!(
        curator_decisions: updated_decisions,
        discogs_refresh: {},
        last_attempted_at: nil
      )
      track_metadata_claims.where(source: "discogs").delete_all
    end
  end

  def claim_groups
    active_claims.to_a.group_by(&:field).sort_by do |field, _claims|
      [ DISPLAY_FIELD_ORDER.index(field) || DISPLAY_FIELD_ORDER.length, field ]
    end
  end

  def curator_summary(claims = active_claims.to_a)
    local_claims = Array(claims)
    release_years = summary_release_years(local_claims)

    {
      release_years: release_years,
      earliest_reliable_year: release_years.select(&:high_confidence_match?)
                                           .min_by { |claim| claim.release_year.to_i },
      classifications: summary_claim_groups(
        local_claims,
        SUMMARY_CLASSIFICATION_FIELDS,
        limit: SUMMARY_CLASSIFICATIONS_PER_SOURCE_LIMIT
      ),
      song_contexts: summary_song_contexts(local_claims),
      signals: summary_signals(local_claims)
    }
  end

  def evidence_state_for(field, claims)
    return "supported" if MULTI_VALUE_FIELDS.include?(field)

    comparable_claims = claims.group_by(&:comparison_scope).values
    return "disputed" if comparable_claims.any? { |group| differing_values?(group) }
    return "confirmed" if comparable_claims.any? { |group| corroborated?(group) }

    "supported"
  end

  def ready?
    status == "ready"
  end

  private

  def decisions
    (curator_decisions || {}).to_h.deep_dup
  end

  def summary_release_years(claims)
    claims.select { |claim| claim.field == "release_date" && claim.release_year.present? }
          .sort_by do |claim|
            [ source_sort_key(claim.source), claim.comparison_scope.to_s, claim.display_value.to_s ]
          end
          .uniq { |claim| [ claim.source, claim.comparison_scope ] }
  end

  def summary_claim_groups(claims, fields, limit:)
    claims.select { |claim| fields.include?(claim.field) }
          # Discogs facts need their own exact source link and attribution.
          # Keep master-family and validated-release evidence separate instead
          # of showing one Discogs URL for a mixed set of facts.
          .group_by { |claim| summary_group_key(claim) }
          .sort_by { |(source, _url, _scope), _source_claims| source_sort_key(source) }
          .filter_map do |group_key, source_claims|
            selected_claims = source_claims
              .sort_by do |claim|
                [
                  DISPLAY_FIELD_ORDER.index(claim.field) || DISPLAY_FIELD_ORDER.length,
                  claim.display_value.to_s.downcase
                ]
              end
              .uniq { |claim| [ claim.field, claim.comparison_scope, claim.comparison_value ] }
              .first(limit)

            [ group_key, selected_claims ] if selected_claims.any?
          end
  end

  def summary_group_key(claim)
    return [ claim.source, nil, nil ] unless claim.discogs?

    [ claim.source, claim.source_url, claim.comparison_scope ]
  end

  def summary_song_contexts(claims)
    claims.select { |claim| claim.field == "song_context" }
          .sort_by { |claim| source_sort_key(claim.source) }
          .first(1)
  end

  def summary_signals(claims)
    summary_claim_groups(
      claims,
      SUMMARY_SIGNAL_FIELDS,
      limit: SUMMARY_SIGNALS_PER_SOURCE_LIMIT
    ).flat_map { |_source, source_claims| source_claims }.first(SUMMARY_SIGNAL_LIMIT)
  end

  def source_sort_key(source)
    SUMMARY_SOURCE_ORDER.index(source.to_s) || SUMMARY_SOURCE_ORDER.length
  end

  def differing_values?(claims)
    claims.map(&:comparison_value).compact.uniq.size > 1
  end

  def corroborated?(claims)
    claims.group_by(&:comparison_value).any? do |_value, same_value_claims|
      same_value_claims.select(&:high_confidence_match?).map(&:source).uniq.size >= 2
    end
  end
end
