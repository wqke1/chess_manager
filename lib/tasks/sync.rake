# Import des nouvelles parties + analyse immédiate, hors serveur web.
#   bin/rails sync
# À planifier avec cron (toutes les 30 min) :
#   */30 * * * * cd ~/Desktop/chess_manager && bin/rails sync >> log/sync.log 2>&1
desc "Importe et analyse les nouvelles parties chess.com"
task sync: :environment do
  new_games = ImportGamesJob.perform_now(CHESSCOM_USER, analyze: false)
  puts "#{Time.now.strftime('%F %R')}  #{new_games.size} nouvelle(s) partie(s)"
  next if new_games.empty?

  engine = Stockfish.new(depth: 14, threads: 2)
  new_games.sort_by(&:played_at).reverse_each do |game|
    result = Analyzer.new(engine).call(game.pgn)
    game.update!(analysis: result, accuracy: result.dig(game.color, "accuracy"), analyzed_at: Time.current)
    puts "  #{game.played_at.to_date}  vs #{game.opponent}  #{result.dig(game.color, 'accuracy')}%"
  end
ensure
  engine&.close
end
