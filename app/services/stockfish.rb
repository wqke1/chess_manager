require "open3"

# Wrapper UCI minimal. Un process Stockfish par instance ; penser à #close.
class Stockfish
  MATE = 10_000

  def initialize(path: STOCKFISH_PATH, depth: STOCKFISH_DEPTH, threads: 2)
    @depth = depth
    @stdin, @stdout, @wait = Open3.popen2(path)
    send "uci";     wait_for "uciok"
    send "setoption name Threads value #{threads}"
    send "isready"; wait_for "readyok"
  end

  # Évalue la position après la séquence de coups UCI depuis la position initiale.
  def evaluate(uci_moves)
    pos = uci_moves.empty? ? "position startpos" : "position startpos moves #{uci_moves.join(' ')}"
    white_to_move = uci_moves.size.even?
    run(pos, white_to_move)
  end

  # Évalue une position donnée en FEN.
  def evaluate_fen(fen)
    run("position fen #{fen}", fen.split[1] == "w")
  end

  def close
    send "quit"
    @stdin.close
    @stdout.close
    @wait.value
  end

  private

  # Retourne { cp: score du point de vue des BLANCS (mat = ±10000), best: "g1f3", pv: ["g1f3", ...] }
  def run(position_cmd, white_to_move)
    send position_cmd
    send "go depth #{@depth}"

    score, pv = 0, []
    while (line = @stdout.gets)
      if line.start_with?("info") && line.include?(" pv ") && line =~ /score (cp|mate) (-?\d+)/
        score = $1 == "cp" ? $2.to_i : ($2.to_i > 0 ? MATE - $2.to_i : -MATE - $2.to_i)
        pv    = line.split(" pv ").last.split.first(8)
      elsif line.start_with?("bestmove")
        bm = line.split[1]
        pv = [bm] if pv.empty? && bm != "(none)"
        break
      end
    end

    # Le score UCI est du point de vue du trait ; on le ramène au point de vue des blancs.
    { cp: white_to_move ? score : -score, best: pv.first, pv: pv }
  end

  def send(cmd) = @stdin.puts(cmd)

  def wait_for(token)
    while (line = @stdout.gets)
      break if line.start_with?(token)
    end
  end
end
