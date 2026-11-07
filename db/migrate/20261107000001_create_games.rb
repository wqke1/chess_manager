class CreateGames < ActiveRecord::Migration[7.0]
  def change
    create_table :games do |t|
      t.string   :uuid, null: false
      t.string   :url
      t.text     :pgn, null: false
      t.string   :white
      t.string   :black
      t.integer  :white_rating
      t.integer  :black_rating
      t.string   :color        # couleur de l'utilisateur : white / black
      t.string   :result       # win / loss / draw (point de vue utilisateur)
      t.string   :time_class   # bullet / blitz / rapid / daily
      t.string   :time_control
      t.string   :opening
      t.datetime :played_at
      t.text     :analysis     # { moves: [...], white: {...}, black: {...} }
      t.float    :accuracy     # précision de l'utilisateur
      t.datetime :analyzed_at
      t.timestamps
    end
    add_index :games, :uuid, unique: true
    add_index :games, :played_at
  end
end
