require "chess"

# Construit le contexte (partie, position, éval Stockfish) et interroge Claude.
class PositionCoach
  SYSTEM = <<~TXT
    Tu es un coach d'échecs qui aide un joueur de club (~850 Elo rapid sur chess.com) à comprendre ses parties.
    Tu réponds en français, de façon concise et concrète (quelques phrases, pas de listes à rallonge).
    Tu t'appuies sur les données du moteur Stockfish fournies (évaluation, meilleure suite) : ne contredis pas le moteur,
    explique plutôt POURQUOI sa suite est bonne (menaces, pièces en prise, cases faibles, activité, sécurité du roi, plans).
    Utilise la notation algébrique (Cf3, Dxd5, O-O). Si tu n'es pas sûr d'un détail tactique, dis-le.
    Évaluation : nombre positif = avantage blanc, en pions. "M3" = mat en 3.
  TXT

  def initialize(game) = @game = game

  # @param ply [Integer] position de la partie (0 = initiale)
  # @param variation [Array<String>] coups SAN joués à la main depuis cette position
  # @param history [Array<Hash>] messages précédents [{role:, content:}]
  def ask(ply:, fen:, variation:, question:, history:)
    engine = Stockfish.new(depth: 14)
    ev = engine.evaluate_fen(fen)
    pv = begin
      g = Chess::Game.load_fen(fen)
      ev[:pv].map { |u| g.move(u) }
    rescue StandardError
      ev[:pv]
    end
    engine.close

    context = <<~TXT
      PARTIE : #{@game.white} (#{@game.white_rating}) - #{@game.black} (#{@game.black_rating}), #{@game.time_class}.
      Le joueur que tu coaches a les #{@game.color == 'white' ? 'blancs' : 'noirs'} (#{@game.color == 'white' ? @game.white : @game.black}).
      Ouverture : #{@game.opening}.

      COUPS JOUÉS JUSQU'ICI : #{moves_text(ply)}
      #{variation.any? ? "VARIANTE TESTÉE PAR LE JOUEUR (depuis cette position) : #{variation.join(' ')}" : ''}

      #{last_move_text(ply) unless variation.any?}

      POSITION ACTUELLE (FEN) : #{fen}
      Trait aux #{fen.split[1] == 'w' ? 'blancs' : 'noirs'}.
      STOCKFISH : évaluation #{eval_text(ev[:cp])}, meilleure suite : #{pv.first(8).join(' ')}
    TXT

    messages = history.last(8).map { |m| { role: m["role"], content: m["content"] } }
    messages << { role: "user", content: "#{context}\n\nQUESTION : #{question}" }
    ClaudeClient.ask(system: SYSTEM, messages: messages)
  end

  private

  def moves_text(ply)
    return "(position initiale)" if ply.zero?
    @game.moves.first(ply).map { |m| m["color"] == "white" ? "#{m['number']}. #{m['san']}" : m["san"] }.join(" ")
  end

  def last_move_text(ply)
    return "" if ply.zero?
    m = @game.moves[ply - 1]
    "DERNIER COUP : #{m['san']} — classé « #{m['class']} » par l'analyse (perte de #{m['loss']}% de chances de gain). " \
      "#{m['comment']} #{m['class'] == 'Meilleur' ? '' : "Meilleure suite à la place : #{(m['pv'] || []).first(6).join(' ')}"}"
  end

  def eval_text(cp)
    return "mat en #{Stockfish::MATE - cp.abs} pour les #{cp > 0 ? 'blancs' : 'noirs'}" if cp.abs >= 9000
    format("%+.2f", cp / 100.0)
  end
end
