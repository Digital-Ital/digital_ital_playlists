class CreateTrackMetadataClaims < ActiveRecord::Migration[8.0]
  def change
    create_table :track_metadata_claims do |t|
      t.references :track_enrichment, null: false, foreign_key: true
      t.string :source, null: false
      t.string :source_identifier
      t.string :source_url
      t.string :field, null: false
      t.json :value, default: {}
      t.string :match_confidence, null: false, default: "supported"
      t.datetime :fetched_at, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :track_metadata_claims,
              [ :track_enrichment_id, :source, :field ],
              name: "index_track_metadata_claims_on_enrichment_source_field"
    add_index :track_metadata_claims, :expires_at
  end
end
