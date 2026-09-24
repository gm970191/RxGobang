import { SIZE, EMPTY, BLACK, WHITE, createBoard, checkWin, isFull, opponent, coordLabel } from "./board.js";
import { LEVELS, chooseMove, openingBias } from "./ai.js";
import { createRenderer } from "./render.js";

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.getRegistrations().then((regs) => {
    regs.forEach((reg) => reg.unregister());
  });
}
if (window.caches) {
  caches.keys().then((keys) => {
    keys.filter((key) => key.startsWith("rxgobang-")).forEach((key) => caches.delete(key));
  });
}

const STORAGE_KEY = "rxgobang-stats";

const els = {
  start: document.getElementById("start-screen"),
  game: document.getElementById("game-screen"),
  modal: document.getElementById("result-modal"),
  levelGrid: document.getElementById("level-grid"),
  canvas: document.getElementById("board"),
  think: document.getElementById("think-veil"),
  turnText: document.getElementById("turn-text"),
  turnDot: document.getElementById("turn-dot"),
  metaLevel: document.getElementById("meta-level"),
  metaDesc: document.getElementById("meta-desc"),
  metaSide: document.getElementById("meta-side"),
  record: document.getElementById("record-list"),
  resultTitle: document.getElementById("result-title"),
  resultSub: document.getElementById("result-sub"),
  resultKicker: document.getElementById("result-kicker"),
  statWin: document.getElementById("stat-win"),
  statLose: document.getElementById("stat-lose"),
  statDraw: document.getElementById("stat-draw"),
};

const renderer = createRenderer(els.canvas);

const settings = { level: 3, human: BLACK };
const state = {
  board: createBoard(),
  moves: [],
  moveIndex: Array.from({ length: SIZE }, () => Array(SIZE).fill(0)),
  turn: BLACK,
  human: BLACK,
  ai: WHITE,
  level: 3,
  over: false,
  thinking: false,
  winLine: null,
  result: null,
  showNumbers: false,
};

let audioCtx = null;

function stats() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || { win: 0, lose: 0, draw: 0 };
  } catch {
    return { win: 0, lose: 0, draw: 0 };
  }
}

function saveStats(next) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  paintStats();
}

function paintStats() {
  const s = stats();
  els.statWin.textContent = s.win;
  els.statLose.textContent = s.lose;
  els.statDraw.textContent = s.draw;
}

function tapSound() {
  try {
    audioCtx = audioCtx || new AudioContext();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = "triangle";
    osc.frequency.value = 210;
    gain.gain.setValueAtTime(0.05, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.1);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(audioCtx.currentTime + 0.1);
  } catch {
    /* ignore autoplay limits */
  }
}

function paintLevels() {
  const current = LEVELS.find((item) => item.id === settings.level);
  els.levelGrid.innerHTML = LEVELS.map((lv) => `
    <button type="button" class="level-card${lv.id === settings.level ? " is-active" : ""}" data-level="${lv.id}">
      ${lv.name}
    </button>
  `).join("");
  const desc = document.getElementById("level-desc");
  if (desc && current) desc.textContent = current.desc;
}

function paintTurn() {
  const humanTurn = state.turn === state.human && !state.over;
  els.turnText.textContent = state.over
    ? state.result === "win" ? "你赢了" : state.result === "lose" ? "你输了" : "和棋"
    : state.thinking ? "对方思考中" : humanTurn ? "请落子" : "等待落子";
  els.turnDot.classList.toggle("is-white", state.turn === WHITE);
}

function paintRecord() {
  const rows = [];
  for (let i = 0; i < state.moves.length; i += 2) {
    const black = state.moves[i];
    const white = state.moves[i + 1];
    rows.push(`<li><span>${i / 2 + 1}</span><span>${black ? coordLabel(black.x, black.y) : ""}</span><span>${white ? coordLabel(white.x, white.y) : ""}</span></li>`);
  }
  els.record.innerHTML = rows.reverse().join("") || "<li><span></span><span>尚无落子</span></li>";
}

function paintMeta() {
  const lv = LEVELS.find((item) => item.id === state.level);
  els.metaLevel.textContent = lv.name;
  els.metaDesc.textContent = lv.desc;
  els.metaSide.textContent = state.human === BLACK ? "执黑先手" : "执白后手";
}

function redraw() {
  renderer.draw(state);
  paintTurn();
  paintRecord();
}

function resetBoard() {
  state.board = createBoard();
  state.moves = [];
  state.moveIndex = Array.from({ length: SIZE }, () => Array(SIZE).fill(0));
  state.turn = BLACK;
  state.over = false;
  state.thinking = false;
  state.winLine = null;
  state.result = null;
  els.modal.classList.add("is-hidden");
  els.modal.hidden = true;
  els.think.classList.add("is-hidden");
}

function startGame() {
  state.human = settings.human;
  state.ai = opponent(settings.human);
  state.level = settings.level;
  resetBoard();
  paintMeta();
  els.start.classList.add("is-hidden");
  els.start.hidden = true;
  els.game.classList.remove("is-hidden");
  els.game.hidden = false;
  redraw();
  if (state.turn === state.ai) scheduleAi();
}

function endGame(result, winLine = null) {
  state.over = true;
  state.thinking = false;
  state.result = result;
  state.winLine = winLine;
  els.think.classList.add("is-hidden");
  const bag = stats();
  if (result === "win") bag.win += 1;
  if (result === "lose") bag.lose += 1;
  if (result === "draw") bag.draw += 1;
  saveStats(bag);
  const map = {
    win: ["对局结束", "你赢了", "五子连珠，落子生风。"],
    lose: ["对局结束", "你输了", "再下一局，棋力自长。"],
    draw: ["对局结束", "和棋", "棋盘已满，未分胜负。"],
  };
  const [kicker, title, sub] = map[result];
  els.resultKicker.textContent = kicker;
  els.resultTitle.textContent = title;
  els.resultSub.textContent = sub;
  els.modal.classList.remove("is-hidden");
  els.modal.hidden = false;
  redraw();
}

function place(x, y, player) {
  state.board[y][x] = player;
  state.moves.push({ x, y, player });
  state.moveIndex[y][x] = state.moves.length;
  tapSound();
  const win = checkWin(state.board, x, y, player);
  if (win) {
    endGame(player === state.human ? "win" : "lose", win);
    return true;
  }
  if (isFull(state.board)) {
    endGame("draw");
    return true;
  }
  state.turn = opponent(player);
  redraw();
  return false;
}

function userMove(x, y) {
  if (state.over || state.thinking || state.turn !== state.human) return;
  if (state.board[y][x] !== EMPTY) return;
  const ended = place(x, y, state.human);
  if (!ended) scheduleAi();
}

function scheduleAi() {
  state.thinking = true;
  els.think.classList.remove("is-hidden");
  paintTurn();
  const delay = 180 + state.level * 90;
  setTimeout(() => {
    try {
      if (state.over) return;
      const open = openingBias(state.board);
      const move = open || chooseMove(state.board, state.ai, state.level);
      state.thinking = false;
      els.think.classList.add("is-hidden");
      if (!move) {
        endGame("draw");
        return;
      }
      place(move.x, move.y, state.ai);
    } catch (err) {
      state.thinking = false;
      els.think.classList.add("is-hidden");
      console.error(err);
    }
  }, delay);
}

function undo() {
  if (state.thinking || state.moves.length === 0) return;
  const revert = () => {
    const last = state.moves.pop();
    if (!last) return;
    state.board[last.y][last.x] = EMPTY;
    state.moveIndex[last.y][last.x] = 0;
  };
  if (state.over) {
    els.modal.classList.add("is-hidden");
    els.modal.hidden = true;
    state.over = false;
    state.result = null;
    state.winLine = null;
  }
  if (state.moves.at(-1)?.player === state.ai) revert();
  if (state.moves.at(-1)?.player === state.human) revert();
  if (state.moves.length === 0 && state.human === WHITE) {
    state.turn = BLACK;
    redraw();
    scheduleAi();
    return;
  }
  state.turn = state.human;
  redraw();
}

function resign() {
  if (state.over || state.thinking) return;
  endGame("lose");
}

els.levelGrid.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-level]");
  if (!btn) return;
  settings.level = Number(btn.dataset.level);
  paintLevels();
});

document.querySelectorAll("[data-side]").forEach((btn) => {
  btn.addEventListener("click", () => {
    settings.human = btn.dataset.side === "white" ? WHITE : BLACK;
    document.querySelectorAll("[data-side]").forEach((node) => node.classList.toggle("is-active", node === btn));
  });
});

document.getElementById("btn-start").addEventListener("click", startGame);
document.getElementById("btn-home").addEventListener("click", () => {
  els.game.classList.add("is-hidden");
  els.game.hidden = true;
  els.start.classList.remove("is-hidden");
  els.start.hidden = false;
  els.modal.classList.add("is-hidden");
});
document.getElementById("btn-undo").addEventListener("click", undo);
document.getElementById("btn-resign").addEventListener("click", resign);
document.getElementById("btn-restart").addEventListener("click", startGame);
document.getElementById("btn-again").addEventListener("click", startGame);
document.getElementById("btn-back").addEventListener("click", () => {
  els.modal.classList.add("is-hidden");
  els.game.classList.add("is-hidden");
  els.game.hidden = true;
  els.start.classList.remove("is-hidden");
  els.start.hidden = false;
});
document.getElementById("chk-numbers").addEventListener("change", (e) => {
  state.showNumbers = e.target.checked;
  redraw();
});

els.canvas.addEventListener("pointermove", (e) => {
  renderer.setHover(state.over ? null : renderer.cellAt(e.clientX, e.clientY));
  renderer.draw(state);
});
els.canvas.addEventListener("pointerleave", () => {
  renderer.setHover(null);
  renderer.draw(state);
});
els.canvas.addEventListener("click", (e) => {
  const cell = renderer.cellAt(e.clientX, e.clientY);
  if (cell) userMove(cell[0], cell[1]);
});

paintLevels();
paintStats();

function loop() {
  if (!els.game.classList.contains("is-hidden")) renderer.draw(state);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
