# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_10_051343) do
  create_table "batch_updates", force: :cascade do |t|
    t.string "status"
    t.integer "current_index"
    t.integer "total_count"
    t.string "current_playlist_title"
    t.integer "changes_count"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.text "description"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position"
    t.integer "parent_id"
    t.string "emoji"
    t.integer "display_order"
    t.boolean "is_main_family"
    t.string "family_color"
    t.string "family_emoji"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "playlist_categories", force: :cascade do |t|
    t.integer "playlist_id", null: false
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_playlist_categories_on_category_id"
    t.index ["playlist_id", "category_id"], name: "index_playlist_categories_on_playlist_id_and_category_id", unique: true
    t.index ["playlist_id"], name: "index_playlist_categories_on_playlist_id"
  end

  create_table "playlist_tracks", force: :cascade do |t|
    t.integer "playlist_id", null: false
    t.integer "track_id", null: false
    t.datetime "added_at"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id"], name: "index_playlist_tracks_on_playlist_id"
    t.index ["track_id"], name: "index_playlist_tracks_on_track_id"
  end

  create_table "playlist_updates", force: :cascade do |t|
    t.integer "update_session_id", null: false
    t.integer "playlist_id", null: false
    t.string "field_name"
    t.string "old_value"
    t.string "new_value"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id"], name: "index_playlist_updates_on_playlist_id"
    t.index ["update_session_id"], name: "index_playlist_updates_on_update_session_id"
  end

  create_table "playlists", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "cover_image_url"
    t.string "spotify_url"
    t.integer "track_count"
    t.string "duration"
    t.integer "category_id"
    t.boolean "featured"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_updated_at"
    t.integer "followers_count", default: 0
    t.index ["category_id"], name: "index_playlists_on_category_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "spotify_id"
    t.string "name"
    t.string "artist"
    t.string "album"
    t.string "image_url"
    t.integer "duration_ms"
    t.string "preview_url"
    t.string "external_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["spotify_id"], name: "index_tracks_on_spotify_id", unique: true
  end

  create_table "update_logs", force: :cascade do |t|
    t.integer "playlist_id", null: false
    t.string "log_type"
    t.string "field_name"
    t.text "old_value"
    t.text "new_value"
    t.integer "track_id", null: false
    t.text "change_summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id"], name: "index_update_logs_on_playlist_id"
    t.index ["track_id"], name: "index_update_logs_on_track_id"
  end

  create_table "update_sessions", force: :cascade do |t|
    t.datetime "started_at"
    t.datetime "completed_at"
    t.string "status"
    t.integer "total_playlists"
    t.integer "updated_playlists"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "playlist_categories", "categories"
  add_foreign_key "playlist_categories", "playlists"
  add_foreign_key "playlist_tracks", "playlists"
  add_foreign_key "playlist_tracks", "tracks"
  add_foreign_key "playlist_updates", "playlists"
  add_foreign_key "playlist_updates", "update_sessions"
  add_foreign_key "update_logs", "playlists"
  add_foreign_key "update_logs", "tracks"
end
