class Game < ApplicationRecord
  validates :uuid, presence: true, uniqueness: true
  validates :pgn, presence: true

  scope :analyzed,   -> { where.not(analyzed_at: nil) }
  scope :unanalyzed, -> { where(analyzed_at: nil) }
  scope :recent,     -> { order(played_at: :desc) }

  DRAWS = %w[agreed repetition stalemate insufficient 50move timevsinsufficient].freeze

  # Construit un Game à partir d'un enregistrement de l'API chess.com.
  def self.from_chesscom(data, user)
    color  = data["white"]["username"].casecmp?(user) ? "white" : "black"
    status = data[color]["result"]
    result = status == "win" ? "win" : (DRAWS.include?(status) ? "draw" : "loss")

    new(
      uuid:         data["uuid"],
      url:          data["url"],
      pgn:          data["pgn"],
      white:        data["white"]["username"],
      black:        data["black"]["username"],
      white_rating: data["white"]["rating"],
      black_rating: data["black"]["rating"],
      color:        color,
      result:       result,
      time_class:   data["time_class"],
      time_control: data["time_control"],
      opening:      opening_name(data["eco"]),
      played_at:    Time.at(data["end_time"]).utc
    )
  end

  # "https://www.chess.com/openings/Sicilian-Defense-Open-2.Nf3-d6" -> "Sicilian Defense"
  def self.opening_name(eco_url)
    return nil if eco_url.blank?
    eco_url.split("/").last.split(/-\d/).first.tr("-", " ")
  end

  # analysis est stockée en texte JSON (SQLite + Rails 7.0 n'ont pas de colonne json native)
  def analysis   = @analysis ||= (self[:analysis] && JSON.parse(self[:analysis]))
  def analysis=(h)
    @analysis = h
    self[:analysis] = h&.to_json
  end

  def analyzed? = analyzed_at.present?
  def opponent  = color == "white" ? black : white
  def my_rating = color == "white" ? white_rating : black_rating
  def moves     = analysis&.dig("moves") || []

  def counts(side = color) = analysis&.dig(side, "counts") || {}
end
