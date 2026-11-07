class AnalyzeGameJob < ApplicationJob
  queue_as :analysis

  def perform(game)
    return if game.analyzed?
    engine = Stockfish.new
    result = Analyzer.new(engine).call(game.pgn)
    game.update!(analysis: result, accuracy: result.dig(game.color, "accuracy"), analyzed_at: Time.current)
  ensure
    engine&.close
  end
end
