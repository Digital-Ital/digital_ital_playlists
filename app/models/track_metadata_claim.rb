class TrackMetadataClaim < ApplicationRecord
  belongs_to :track_enrichment

  validates :source, :field, :match_confidence, :fetched_at, presence: true

  def display_value
    claim_data["text"].presence || claim_data["name"].presence || value.to_s
  end

  def context
    claim_data["context"].presence
  end

  def comparison_value
    (claim_data["comparison"].presence || display_value).to_s.downcase.squish.presence
  end

  def comparison_scope
    claim_data["scope"].presence || field
  end

  def high_confidence_match?
    %w[spotify_id isrc_exact curator_selected_release].include?(match_confidence)
  end

  def confidence_label
    {
      "spotify_id" => "Spotify recording match",
      "isrc_exact" => "ISRC recording match",
      "curator_selected_release" => "Curator-selected release",
      "candidate_title_artist_duration" => "Title / artist / duration candidate"
    }.fetch(match_confidence, match_confidence.to_s.humanize)
  end

  def source_label
    {
      "spotify" => "Spotify",
      "musicbrainz" => "MusicBrainz",
      "discogs" => "Discogs"
    }.fetch(source, source.to_s.humanize)
  end

  def temporary?
    expires_at.present?
  end

  private

  def claim_data
    value.is_a?(Hash) ? value : {}
  end
end
