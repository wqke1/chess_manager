# Analyse en masse, en parallèle, hors du serveur web.
#   bin/rails analyze              # 4 moteurs, profondeur 14
#   bin/rails analyze[6,12]        # 6 moteurs, profondeur 12
# Ctrl+C pour arrêter ; relancer reprend sur les parties non analysées (les plus récentes d'abord).
desc "Analyse toutes les parties non analysées (parallèle)"
task :analyze, [:workers, :depth] => :environment do |_, args|
  workers = (args[:workers] || 4).to_i
  depth   = (args[:depth] || 14).to_i
  queue   = Queue.new
  Game.unanalyzed.recent.pluck(:id).each { |id| queue << id }
  total = queue.size
  done  = 0
  mutex = Mutex.new
  started = Time.now
  puts "#{total} parties à analyser, #{workers} moteurs, profondeur #{depth}"

  threads = workers.times.map do
    Thread.new do
      engine = Stockfish.new(depth: depth, threads: 1)
      while (id = (queue.pop(true) rescue nil))
        begin
          game = Game.find(id)
          result = Analyzer.new(engine).call(game.pgn)
          game.update!(analysis: result, accuracy: result.dig(game.color, "accuracy"), analyzed_at: Time.current)
          mutex.synchronize do
            done += 1
            rate = (Time.now - started) / done
            eta  = ((total - done) * rate / 60).round
            puts "#{done}/#{total}  #{game.played_at.to_date}  vs #{game.opponent}  #{result.dig(game.color, 'accuracy')}%   (reste ~#{eta} min)"
          end
        rescue => e
          warn "Partie #{id} : #{e.class} #{e.message}"
        end
      end
    ensure
      engine&.close
    end
  end
  threads.each(&:join)
  puts "Terminé en #{((Time.now - started) / 60).round} min."
end
