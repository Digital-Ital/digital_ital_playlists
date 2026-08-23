class TrackEnrichment < ApplicationRecord
  DISPLAY_FIELD_ORDER = %w[
    isrc
    release_date
    release_country
    release_title
    release_position
    label
    catalogue_number
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

  MULTI_VALUE_FIELDS = %w[
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

  belongs_to :track
  has_many :track_metadata_claims, dependent: :destroy

  validates :status, presence: true

  def active_claims
    track_metadata_claims.where("expires_at IS NULL OR expires_at > ?", Time.current)
  end

  def expire_temporary_claims!
    track_metadata_claims.where(source: "discogs")
                         .where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
                         .delete_all
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

      update!(curator_decisions: updated_decisions)
      track_metadata_claims.where(source: "discogs").delete_all
    end
  end

  def claim_groups
    active_claims.to_a.group_by(&:field).sort_by do |field, _claims|
      [ DISPLAY_FIELD_ORDER.index(field) || DISPLAY_FIELD_ORDER.length, field ]
    end
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

  def differing_values?(claims)
    claims.map(&:comparison_value).compact.uniq.size > 1
  end

  def corroborated?(claims)
    claims.group_by(&:comparison_value).any? do |_value, same_value_claims|
      same_value_claims.select(&:high_confidence_match?).map(&:source).uniq.size >= 2
    end
  end
end
