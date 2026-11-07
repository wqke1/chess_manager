require "chess"

# Analyse une partie coup par coup avec Stockfish et classe chaque coup
# (Meilleur / Excellent / Bon / Imprécision / Erreur / Gaffe) à la manière
# du Game Review de chess.com. Formules de précision/win% : celles de Lichess.
class Analyzer
  # seuil (points de probabilité de gain perdus) => classe
  CLASSES = [[0.0, "Meilleur"], [2.0, "Excellent"], [5.0, "Bon"],
             [10.0, "Imprécision"], [20.0, "Erreur"], [Float::INFINITY, "Gaffe"]].freeze
  CLASS_NAMES = CLASSES.map(&:last).freeze
  PIECES = { "p" => "le pion", "n" => "le cavalier", "b" => "le fou", "r" => "la tour", "q" => "la dame" }.freeze
  MATE_THRESHOLD = 9_000

  def initialize(engine) = @engine = engine

  # @param pgn [String] PGN chess.com (commentaires d'horloge tolérés)
  # @return [Hash] { "moves" => [...], "white" => {...}, "black" => {...} }
  def call(pgn)
    sans  = extract_sans(pgn)
    game  = Chess::Game.new
    ucis  = []
    moves = []

    prev = @engine.evaluate([])
    sans.each_with_index do |san, i|
      mover    = game.active_player           # :white / :black
      fen_before = game.board.to_fen
      game.move(san)
      ucis << to_uci(game.coord_moves.last)
      cur = @engine.evaluate(ucis)

      before, after = win_pct(prev[:cp]), win_pct(cur[:cp])
      loss = mover == :white ? before - after : after - before
      loss = [loss, 0.0].max
      klass = ucis.last == prev[:best] ? "Meilleur" : classify(loss)

      pv_san = pv_to_san(sans[0...i], prev[:pv])
      m = {
        "ply"      => i + 1,
        "number"   => i / 2 + 1,
        "color"    => mover.to_s,
        "san"      => san,
        "uci"      => ucis.last,
        "fen"      => game.board.to_fen,
        "best"     => pv_san.first,
        "best_uci" => prev[:best],
        "pv"       => pv_san,
        "eval_cp"  => cur[:cp],
        "loss"     => loss.round(1),
        "class"    => klass
      }
      m["comment"] = comment(m, mover, fen_before, prev, cur, pv_to_san(sans[0..i], cur[:pv]))
      moves << m
      prev = cur
    end

    result = { "moves" => moves }
    %w[white black].each do |color|
      own = moves.select { |m| m["color"] == color }
      counts = CLASS_NAMES.to_h { |n| [n, 0] }
      own.each { |m| counts[m["class"]] += 1 }
      result[color] = { "accuracy" => accuracy(own.map { |m| m["loss"] }).round(1), "counts" => counts }
    end
    result
  end

  private

  # ---------- commentaires ----------

  def comment(m, mover, fen_before, prev, cur, reply_pv)
    sign     = mover == :white ? 1 : -1
    best     = m["best"]
    line     = m["pv"].first(6).join(" ")
    mate_before = sign * prev[:cp] >= MATE_THRESHOLD   # le joueur avait un mat
    mate_after  = sign * cur[:cp]  <= -MATE_THRESHOLD  # l'adversaire a un mat

    case m["class"]
    when "Meilleur"
      mate_before ? "Le meilleur coup, le mat approche." : "Le meilleur coup."
    when "Excellent"
      "Excellent. Le moteur préfère de peu #{best}."
    when "Bon"
      "Un bon coup. Plus précis : #{best}."
    else
      return "Mat forcé manqué : #{line}." if mate_before && !(sign * cur[:cp] >= MATE_THRESHOLD)
      return "Permet un mat forcé : #{reply_pv.first(6).join(' ')}." if mate_after && !(sign * prev[:cp] <= -MATE_THRESHOLD)

      hanging = hanging_piece(m["fen"], cur[:pv])
      return "Laisse #{hanging} en prise (#{reply_pv.first}). Il fallait #{best} : #{line}." if hanging

      captured = piece_at(fen_before, prev[:best].to_s[2, 2])
      if captured && prev[:best] != m["uci"]
        return "Manque #{best}, qui gagnait #{PIECES[captured.downcase]}. Suite : #{line}."
      end

      "#{m['class']}. Il fallait #{best} : #{line}."
    end
  end

  # La meilleure réponse adverse capture une pièce que la suite ne reprend pas.
  def hanging_piece(fen_after, pv)
    return nil if pv.empty?
    sq = pv[0][2, 2]
    piece = piece_at(fen_after, sq)
    return nil unless piece
    return nil if pv[1] && pv[1][2, 2] == sq  # reprise immédiate : échange, pas une pièce en prise
    PIECES[piece.downcase]
  end

  # Pièce sur une case ("e4") d'un FEN, ou nil.
  def piece_at(fen, square)
    return nil unless square&.match?(/^[a-h][1-8]$/)
    rows = fen.split.first.split("/")
    row  = rows[8 - square[1].to_i]
    col  = square[0].ord - "a".ord
    expanded = row.gsub(/\d/) { |d| "." * d.to_i }
    expanded[col] == "." ? nil : expanded[col]
  end

  # ---------- utilitaires ----------

  # Retire en-têtes, commentaires {...}, numéros de coups, résultat → liste de SAN.
  def extract_sans(pgn)
    body = pgn.lines.reject { |l| l.start_with?("[") }.join(" ")
    body = body.gsub(/\{[^}]*\}/, "").gsub(/\([^)]*\)/, "").gsub(/\$\d+/, "")
    body.split.reject { |t| t.match?(/^\d+\.+$/) || %w[1-0 0-1 1/2-1/2 *].include?(t) }
        .map { |t| t.sub(/^\d+\.+/, "") }.reject(&:empty?)
  end

  def to_uci(coord) = coord.delete("=").downcase  # "b7a8=Q" -> "b7a8q"

  # Convertit une variante UCI en SAN à partir de la position après `sans_before`.
  def pv_to_san(sans_before, pv_uci)
    g = Chess::Game.new(sans_before)
    out = []
    pv_uci.each { |u| out << g.move(u) }
    out
  rescue StandardError
    out.empty? ? pv_uci : out
  end

  def win_pct(cp) = 50 + 50 * (2 / (1 + Math.exp(-0.00368208 * cp)) - 1)

  def classify(loss) = CLASSES.find { |t, _| loss <= t }.last

  def accuracy(losses)
    return 100.0 if losses.empty?
    losses.sum { |l| (103.1668 * Math.exp(-0.04354 * l) - 3.1669).clamp(0, 100) } / losses.size
  end
end
