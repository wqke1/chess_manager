# Chess Manager

Analyse de parties chess.com (type Game Review) en local, avec historique et stats.

## Setup

    brew install stockfish
    bundle add chess          # parsing PGN/SAN
    bin/rails db:migrate
    bin/rails server

Puis http://localhost:3000 → « Importer les nouvelles parties » → « Analyser ».

## Config (variables d'environnement, optionnelles)

- `CHESSCOM_USER` — pseudo chess.com (défaut : wqkedp)
- `STOCKFISH` — chemin du binaire (défaut : `stockfish` dans le PATH)
- `STOCKFISH_DEPTH` — profondeur d'analyse (défaut : 16 ; 12 = rapide, 20 = précis)

## Structure

- `app/services/chesscom.rb` — client API chess.com (public, sans clé)
- `app/services/stockfish.rb` — wrapper UCI
- `app/services/analyzer.rb` — classification des coups + précision (formules Lichess)
- `app/jobs/import_games_job.rb` — import des nouveaux mois
- `app/jobs/analyze_game_job.rb` — analyse d'une partie, résultat stocké en JSON dans `games.analysis`
- `app/javascript/controllers/board_controller.js` — échiquier (chessground), barre d'éval, navigation clavier (← → ↑ ↓)

## Ligne de commande (sans le site)

`analyze.py` est l'équivalent Python autonome : `python3 analyze.py --last 3`.
