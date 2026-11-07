class GamesController < ApplicationController
  def index
    @games = Game.recent
    @games = @games.where(time_class: params[:time_class]) if params[:time_class].present?
    @games = @games.limit(200)
    @pending = Game.unanalyzed.count
  end

  def show
    @game = Game.find(params[:id])
  end

  # (Ré)analyse une partie.
  def analyze
    game = Game.find(params[:id])
    game.update!(analysis: nil, accuracy: nil, analyzed_at: nil)
    AnalyzeGameJob.perform_later(game)
    redirect_to game, notice: "Analyse lancée."
  end

  def analyze_all
    Game.unanalyzed.recent.find_each { |g| AnalyzeGameJob.perform_later(g) }
    redirect_to games_path, notice: "Analyses lancées."
  end

  def import
    ImportGamesJob.perform_later
    redirect_to games_path, notice: "Import lancé, recharge dans quelques secondes."
  end

  # Chat : question sur la position courante, répondue par Claude avec le contexte Stockfish.
  def ask
    game = Game.find(params[:id])
    answer = PositionCoach.new(game).ask(
      ply: params[:ply].to_i, fen: params.require(:fen),
      variation: Array(params[:variation]), question: params.require(:question),
      history: Array(params[:history]).map { |h| h.permit(:role, :content).to_h }
    )
    render json: { answer: answer }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  # Évaluation à la volée d'une position (pour les variantes jouées sur l'échiquier).
  def eval
    fen = params.require(:fen)
    engine = Stockfish.new(depth: [STOCKFISH_DEPTH, 14].min)
    r = engine.evaluate_fen(fen)
    g = Chess::Game.load_fen(fen)
    pv_san = r[:pv].map { |u| g.move(u) } rescue r[:pv]
    render json: { cp: r[:cp], best_uci: r[:best], pv: pv_san }
  ensure
    engine&.close
  end
end
