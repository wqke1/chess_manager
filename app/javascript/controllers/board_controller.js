import { Controller } from "@hotwired/stimulus"
import { Chessground } from "chessground"
import { Chess } from "chess.js"

const START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const PAUSE_ON = ["Imprécision", "Erreur", "Gaffe"]
const LABEL = { "Meilleur": "✓ Meilleur coup", "Excellent": "Excellent", "Bon": "Bon coup",
                "Imprécision": "?! Imprécision", "Erreur": "? Erreur", "Gaffe": "?? Gaffe" }

export default class extends Controller {
  static targets = ["board", "evalFill", "evalText", "comment", "list", "variation", "variationMoves", "variationEval", "play", "chatLog", "chatInput", "chatSend"]
  static values = { moves: Array, orientation: String }

  connect() {
    this.ply = 0
    this.variation = []          // coups joués à la main : [{ san, uci, fen }]
    this.cg = Chessground(this.boardTarget, {
      fen: START, orientation: this.orientationValue, coordinates: true,
      movable: { free: false, color: "both", events: { after: (o, d) => this.userMove(o, d) } },
      draggable: { showGhost: true }
    })
    this.onKey = (e) => {
      if (e.target.tagName === "INPUT") return
      if (e.key === " ") { e.preventDefault(); this.togglePlay(); return }
      if (["ArrowLeft","ArrowRight","ArrowUp","ArrowDown"].includes(e.key)) this.stop()
      if (e.key === "ArrowLeft") this.prev()
      if (e.key === "ArrowRight") this.next()
      if (e.key === "ArrowUp") this.first()
      if (e.key === "ArrowDown") this.last()
      if (e.key === "Escape") this.exitVariation()
    }
    document.addEventListener("keydown", this.onKey)
    const anchor = location.hash.match(/ply-(\d+)/)
    this.show(anchor ? parseInt(anchor[1]) : 0)
  }

  disconnect() { this.stop(); document.removeEventListener("keydown", this.onKey) }

  // ---- lecture automatique ----
  togglePlay() { this.timer ? this.stop() : this.play() }
  play() {
    if (this.ply >= this.movesValue.length) this.show(0)
    this.timer = setInterval(() => {
      if (this.ply >= this.movesValue.length) return this.stop()
      this.show(this.ply + 1)
      if (PAUSE_ON.includes(this.movesValue[this.ply - 1].class)) this.stop()  // on s'arrête sur les coups à regarder
    }, 1500)
    this.playTarget.textContent = "⏸"
  }
  stop() {
    clearInterval(this.timer); this.timer = null
    if (this.hasPlayTarget) this.playTarget.textContent = "▶ auto"
  }

  // ---- navigation dans la partie ----
  first() { this.show(0) }
  last()  { this.show(this.movesValue.length) }
  prev()  { this.variation.length ? this.undoVariation() : this.show(Math.max(0, this.ply - 1)) }
  next()  { if (!this.variation.length) this.show(Math.min(this.movesValue.length, this.ply + 1)) }
  flip()  { this.cg.toggleOrientation(); this.render() }
  goto(e) { this.stop(); this.show(parseInt(e.currentTarget.dataset.ply)) }

  show(ply) {
    this.ply = ply
    this.variation = []
    this.render()
  }

  // Position de base = position de la partie au ply courant.
  get baseFen() { return this.ply > 0 ? this.movesValue[this.ply - 1].fen : START }
  get currentFen() { return this.variation.length ? this.variation[this.variation.length - 1].fen : this.baseFen }

  render() {
    const m = this.ply > 0 ? this.movesValue[this.ply - 1] : null
    const inVar = this.variation.length > 0
    const last = inVar ? this.variation[this.variation.length - 1] : m
    const chess = new Chess(this.currentFen)

    this.cg.set({
      fen: this.currentFen,
      lastMove: last ? [last.uci.slice(0, 2), last.uci.slice(2, 4)] : undefined,
      turnColor: chess.turn() === "w" ? "white" : "black",
      movable: { color: "both", dests: this.dests(chess) },
      check: chess.inCheck()
    })

    // Liste des coups : surligne le coup courant
    this.listTarget.querySelectorAll(".mv").forEach(el => el.classList.toggle("current", parseInt(el.dataset.ply) === this.ply))
    const cur = this.listTarget.querySelector(".mv.current")
    if (cur) cur.scrollIntoView({ block: "nearest" })

    this.variationTarget.hidden = !inVar
    if (inVar) return  // l'éval et la flèche viennent du serveur (voir userMove)

    // Éval + flèche du meilleur coup dans la position courante
    const nextMove = this.movesValue[this.ply]   // le coup suivant de la partie porte le "best" de cette position
    this.renderEval(m ? m.eval_cp : 20)
    this.setArrow(nextMove ? nextMove.best_uci : null)

    // Commentaire sur le coup qui vient d'être joué
    if (!m) {
      this.commentTarget.innerHTML = "<b>Position initiale</b>"
      this.commentTarget.className = "comment"
      return
    }
    const pv = m.pv && m.pv.length ? `<div class="pv">Meilleure suite : ${m.pv.slice(0, 6).join(" ")}</div>` : ""
    this.commentTarget.innerHTML = `<b>${m.number}${m.color === "white" ? "." : "..."} ${m.san} — ${LABEL[m.class]}</b><div>${m.comment || ""}</div>${m.class === "Meilleur" ? "" : pv}`
    this.commentTarget.className = `comment cls-${slug(m.class)}`
  }

  // ---- variantes jouées à la main ----
  async userMove(orig, dest) {
    this.stop()
    const chess = new Chess(this.currentFen)
    const mv = chess.move({ from: orig, to: dest, promotion: "q" })
    if (!mv) { this.render(); return }
    this.variation.push({ san: mv.san, uci: orig + dest + (mv.promotion || ""), fen: chess.fen() })
    this.render()
    this.variationMovesTarget.textContent = this.variationLine()
    this.variationEvalTarget.textContent = "Stockfish réfléchit…"
    this.setArrow(null)

    const fen = this.currentFen
    const r = await fetch(`/eval?fen=${encodeURIComponent(fen)}`).then(r => r.json())
    if (fen !== this.currentFen) return  // l'utilisateur a bougé entre-temps
    this.renderEval(r.cp)
    this.setArrow(r.best_uci)
    this.variationEvalTarget.textContent = r.pv.length ? `Meilleur : ${r.pv[0]}  —  suite : ${r.pv.slice(0, 6).join(" ")}` : "Fin de partie."
  }

  undoVariation() { this.variation.pop(); this.render(); if (this.variation.length) this.variationMovesTarget.textContent = this.variationLine() }
  exitVariation() { this.variation = []; this.render() }

  variationLine() {
    const base = new Chess(this.baseFen)
    let n = base.moveNumber(), white = base.turn() === "w"
    return this.variation.map((v, i) => {
      const prefix = (i === 0 && !white) ? `${n}... ` : (white ? `${n}. ` : "")
      const s = prefix + v.san
      if (!white) n++
      white = !white
      return s
    }).join(" ")
  }

  // ---- chat (Claude + contexte Stockfish) ----
  async ask(e) {
    e.preventDefault()
    const q = this.chatInputTarget.value.trim()
    if (!q || this.asking) return
    this.chatInputTarget.value = ""
    this.asking = true
    this.chatSendTarget.disabled = true
    this.chat = this.chat || []
    this.addMsg("user", q)
    const pending = this.addMsg("assistant", "…")
    try {
      const r = await fetch(`${location.pathname}/ask`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content },
        body: JSON.stringify({ ply: this.ply, fen: this.currentFen, variation: this.variation.map(v => v.san), question: q, history: this.chat })
      }).then(r => r.json())
      pending.textContent = r.answer || `Erreur : ${r.error}`
      if (r.answer) this.chat.push({ role: "user", content: q }, { role: "assistant", content: r.answer })
    } catch (err) {
      pending.textContent = `Erreur : ${err}`
    } finally {
      this.asking = false
      this.chatSendTarget.disabled = false
      this.chatInputTarget.focus()
    }
  }

  addMsg(role, text) {
    const div = document.createElement("div")
    div.className = `msg ${role}`
    div.textContent = text
    this.chatLogTarget.appendChild(div)
    this.chatLogTarget.scrollTop = this.chatLogTarget.scrollHeight
    return div
  }

  // ---- helpers ----
  dests(chess) {
    const map = new Map()
    for (const mv of chess.moves({ verbose: true })) {
      if (!map.has(mv.from)) map.set(mv.from, [])
      map.get(mv.from).push(mv.to)
    }
    return map
  }

  setArrow(uci) {
    this.cg.setAutoShapes(uci ? [{ orig: uci.slice(0, 2), dest: uci.slice(2, 4), brush: "green" }] : [])
  }

  renderEval(cp) {
    const mate = Math.abs(cp) >= 9000
    const pct = mate ? (cp > 0 ? 100 : 0) : 50 + 50 * (2 / (1 + Math.exp(-0.004 * cp)) - 1)
    const whiteBottom = this.cg.state.orientation === "white"
    this.evalFillTarget.style.height = `${pct}%`
    this.evalFillTarget.style[whiteBottom ? "bottom" : "top"] = "0"
    this.evalFillTarget.style[whiteBottom ? "top" : "bottom"] = "auto"
    this.evalTextTarget.textContent = mate ? `M${10000 - Math.abs(cp)}` : (cp / 100).toFixed(1)
  }
}

function slug(s) { return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }
