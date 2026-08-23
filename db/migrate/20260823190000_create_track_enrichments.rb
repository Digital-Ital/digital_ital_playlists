class CreateTrackEnrichments < ActiveRecord::Migration[8.0]
  def change
    create_table :track_enrichments do |t|
      t.references :track, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.datetime :last_refreshed_at
      t.datetime :last_attempted_at
      t.text :last_error
      t.json :curator_decisions, default: {}

      t.timestamps
    end
  end
end
