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

ActiveRecord::Schema[8.0].define(version: 2025_10_07_033654) do
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
    t.index ["category_id"], name: "index_playlists_on_category_id"
  end

  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "playlist_categories", "categories"
  add_foreign_key "playlist_categories", "playlists"
end
