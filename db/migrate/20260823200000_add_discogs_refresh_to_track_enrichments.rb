class AddDiscogsRefreshToTrackEnrichments < ActiveRecord::Migration[8.0]
  def change
    add_column :track_enrichments, :discogs_refresh, :json, null: false, default: {}
  end
end
