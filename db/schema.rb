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

ActiveRecord::Schema[7.0].define(version: 2026_11_07_000001) do
  create_table "games", force: :cascade do |t|
    t.string "uuid", null: false
    t.string "url"
    t.text "pgn", null: false
    t.string "white"
    t.string "black"
    t.integer "white_rating"
    t.integer "black_rating"
    t.string "color"
    t.string "result"
    t.string "time_class"
    t.string "time_control"
    t.string "opening"
    t.datetime "played_at"
    t.text "analysis"
    t.float "accuracy"
    t.datetime "analyzed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["played_at"], name: "index_games_on_played_at"
    t.index ["uuid"], name: "index_games_on_uuid", unique: true
  end

end
