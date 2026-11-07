#!/usr/bin/env python3
"""
Analyseur de parties chess.com — équivalent minimal du "Game Review".

Usage :
    python analyze.py <username>                 # dernière partie du joueur
    python analyze.py <username> --last 5        # 5 dernières parties
    python analyze.py <username> --month 2026/10 # tout le mois
    python analyze.py --pgn partie.pgn           # un fichier PGN local

Options :
    --depth N     profondeur Stockfish (défaut 16 ; 12 = rapide, 20 = précis)
    --json        sort aussi un fichier JSON par partie dans ./reports/
    --engine PATH chemin vers le binaire Stockfish (sinon $STOCKFISH, puis PATH)
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import shutil
import sys
from pathlib import Path

import chess
import chess.engine
import chess.pgn
import requests

DEFAULT_USER = "wqkedp"
USER_AGENT = "chess-manager/0.1 (perso ; contact: wqkev2@gmail.com)"
API = "https://api.chess.com/pub/player/{user}/games"

# Seuils de classification, en points de "probabilité de gain" perdus (0-100)
CLASSES = [
    (0.0, "Meilleur"),
    (2.0, "Excellent"),
    (5.0, "Bon"),
    (10.0, "Imprécision"),
    (20.0, "Erreur"),
    (math.inf, "Gaffe"),
]
SYMBOL = {"Meilleur": "!", "Excellent": "", "Bon": "", "Imprécision": "?!", "Erreur": "?", "Gaffe": "??"}


# ---------- chess.com ----------

def fetch_games(user: str, month: str | None, last: int) -> list[dict]:
    s = requests.Session()
    s.headers["User-Agent"] = USER_AGENT
    if month:
        r = s.get(f"{API.format(user=user)}/{month}")
        r.raise_for_status()
        return r.json()["games"]
    archives = s.get(f"{API.format(user=user)}/archives")
    archives.raise_for_status()
    games: list[dict] = []
    for url in reversed(archives.json()["archives"]):  # du plus récent au plus ancien
        r = s.get(url)
        r.raise_for_status()
        games = r.json()["games"] + games
        if len(games) >= last:
            break
    return games[-last:]


def pgn_to_game(pgn: str) -> chess.pgn.Game:
    return chess.pgn.read_game(io.StringIO(pgn))


# ---------- évaluation ----------

def win_pct(cp: int) -> float:
    """Centipions -> probabilité de gain (0-100), formule Lichess."""
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)


def score_cp(score: chess.engine.PovScore) -> int:
    """Score du point de vue des blancs, mat converti en ±10000."""
    return score.white().score(mate_score=10000)


def classify(loss: float) -> str:
    for threshold, name in CLASSES:
        if loss <= threshold:
            return name
    return "Gaffe"


def accuracy_from_losses(losses: list[float]) -> float:
    """Précision à la Lichess : moyenne des précisions par coup."""
    if not losses:
        return 100.0
    accs = [max(0.0, min(100.0, 103.1668 * math.exp(-0.04354 * l) - 3.1669)) for l in losses]
    return sum(accs) / len(accs)


def analyze_game(game: chess.pgn.Game, engine: chess.engine.SimpleEngine, depth: int) -> dict:
    board = game.board()
    limit = chess.engine.Limit(depth=depth)
    info = engine.analyse(board, limit)
    prev_cp = score_cp(info["score"])
    prev_best = info.get("pv", [None])[0]

    moves = []
    for move in game.mainline_moves():
        mover = board.turn  # chess.WHITE / chess.BLACK
        san = board.san(move)
        best_san = board.san(prev_best) if prev_best else None
        board.push(move)
        info = engine.analyse(board, limit)
        cp = score_cp(info["score"])

        before, after = win_pct(prev_cp), win_pct(cp)
        loss = (before - after) if mover == chess.WHITE else (after - before)
        loss = max(0.0, loss)
        cls = "Meilleur" if move == prev_best else classify(loss)

        moves.append({
            "ply": board.ply(),
            "move_number": (board.ply() + 1) // 2,
            "color": "white" if mover == chess.WHITE else "black",
            "san": san,
            "best": best_san,
            "eval_cp": cp,
            "loss": round(loss, 1),
            "class": cls,
        })
        prev_cp, prev_best = cp, info.get("pv", [None])[0]

    out = {"moves": moves}
    for color in ("white", "black"):
        own = [m for m in moves if m["color"] == color]
        counts = {name: 0 for _, name in CLASSES}
        for m in own:
            counts[m["class"]] += 1
        out[color] = {
            "accuracy": round(accuracy_from_losses([m["loss"] for m in own]), 1),
            "counts": counts,
        }
    return out


# ---------- sortie ----------

def print_report(meta: dict, result: dict) -> None:
    w, b = meta.get("white", {}), meta.get("black", {})
    print("=" * 70)
    print(f"{w.get('username', '?')} ({w.get('rating', '?')})  vs  "
          f"{b.get('username', '?')} ({b.get('rating', '?')})   "
          f"[{meta.get('time_class', '')} {meta.get('time_control', '')}]")
    if meta.get("url"):
        print(meta["url"])
    print(f"Précision : blancs {result['white']['accuracy']}%  |  noirs {result['black']['accuracy']}%")
    for color, label in (("white", "Blancs"), ("black", "Noirs")):
        c = result[color]["counts"]
        print(f"  {label:6}: " + "  ".join(f"{k} {v}" for k, v in c.items() if v))
    print("-" * 70)
    for m in result["moves"]:
        if m["class"] in ("Imprécision", "Erreur", "Gaffe"):
            num = f"{m['move_number']}." if m["color"] == "white" else f"{m['move_number']}..."
            ev = m["eval_cp"] / 100
            print(f"{num:>6} {m['san']:<7}{SYMBOL[m['class']]:<3} {m['class']:<12} "
                  f"(-{m['loss']:.0f}%)  meilleur : {m['best']}   éval {ev:+.2f}")
    print()


def find_engine(path: str | None) -> str:
    for candidate in (path, os.environ.get("STOCKFISH"), shutil.which("stockfish"),
                      str(Path(__file__).parent / "stockfish")):
        if candidate and Path(candidate).exists():
            return candidate
    sys.exit("Stockfish introuvable : brew install stockfish, ou --engine /chemin/stockfish")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("username", nargs="?", default=DEFAULT_USER)
    ap.add_argument("--pgn")
    ap.add_argument("--month")
    ap.add_argument("--last", type=int, default=1)
    ap.add_argument("--depth", type=int, default=16)
    ap.add_argument("--engine")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if args.pgn:
        games = [{"pgn": Path(args.pgn).read_text()}]
    elif args.username:
        games = fetch_games(args.username, args.month, args.last)
    else:
        ap.error("donne un username chess.com ou --pgn")

    engine = chess.engine.SimpleEngine.popen_uci(find_engine(args.engine))
    try:
        for meta in games:
            game = pgn_to_game(meta["pgn"])
            if game is None:
                continue
            if not meta.get("white"):  # PGN local : métadonnées depuis les en-têtes
                h = game.headers
                meta.update(white={"username": h.get("White"), "rating": h.get("WhiteElo")},
                            black={"username": h.get("Black"), "rating": h.get("BlackElo")})
            result = analyze_game(game, engine, args.depth)
            print_report(meta, result)
            if args.json:
                Path("reports").mkdir(exist_ok=True)
                name = meta.get("url", "local").rstrip("/").split("/")[-1]
                Path(f"reports/{name}.json").write_text(
                    json.dumps({"meta": {k: v for k, v in meta.items() if k != "pgn"}, **result},
                               ensure_ascii=False, indent=1))
    finally:
        engine.quit()


if __name__ == "__main__":
    main()
