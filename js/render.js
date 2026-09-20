import { SIZE, EMPTY, BLACK } from "./board.js";

const STARS = [
  [3, 3],
  [3, 11],
  [11, 3],
  [11, 11],
  [7, 7],
];

export function createRenderer(canvas) {
  const ctx = canvas.getContext("2d");
  const pad = 36;
  let hover = null;
  let pulse = 0;

  function metrics() {
    const size = canvas.width;
    const cell = (size - pad * 2) / (SIZE - 1);
    return { size, cell, pad };
  }

  function point(x, y) {
    const { cell, pad: p } = metrics();
    return [p + x * cell, p + y * cell];
  }

  function cellAt(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const scale = canvas.width / rect.width;
    const px = (clientX - rect.left) * scale;
    const py = (clientY - rect.top) * scale;
    const { cell, pad: p } = metrics();
    const x = Math.round((px - p) / cell);
    const y = Math.round((py - p) / cell);
    if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return null;
    return [x, y];
  }

  function drawWood() {
    const { size } = metrics();
    const g = ctx.createLinearGradient(0, 0, size, size);
    g.addColorStop(0, "#e7c796");
    g.addColorStop(0.5, "#d4a56b");
    g.addColorStop(1, "#c0894e");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, size, size);
    ctx.strokeStyle = "rgba(120, 70, 28, 0.07)";
    ctx.lineWidth = 6;
    for (let i = 0; i < 9; i += 1) {
      ctx.beginPath();
      ctx.moveTo(-20, i * size / 8);
      ctx.lineTo(size + 20, i * size / 8 + 18);
      ctx.stroke();
    }
  }

  function drawGrid() {
    const { cell, pad: p } = metrics();
    ctx.strokeStyle = "rgba(72, 42, 18, 0.78)";
    ctx.lineWidth = 1.2;
    for (let i = 0; i < SIZE; i += 1) {
      ctx.beginPath();
      ctx.moveTo(p, p + i * cell);
      ctx.lineTo(p + (SIZE - 1) * cell, p + i * cell);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(p + i * cell, p);
      ctx.lineTo(p + i * cell, p + (SIZE - 1) * cell);
      ctx.stroke();
    }
    ctx.fillStyle = "#4a2c12";
    for (const [x, y] of STARS) {
      const [px, py] = point(x, y);
      ctx.beginPath();
      ctx.arc(px, py, 4.2, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function drawStone(x, y, player, marked, winning, number) {
    const [px, py] = point(x, y);
    const r = metrics().cell * 0.42;
    if (winning) {
      ctx.beginPath();
      ctx.arc(px, py, r + 6 + Math.sin(pulse / 8) * 1.6, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(196, 64, 48, 0.38)";
      ctx.fill();
      ctx.beginPath();
      ctx.arc(px, py, r + 2, 0, Math.PI * 2);
      ctx.strokeStyle = "#e8c36a";
      ctx.lineWidth = 3;
      ctx.stroke();
    }
    const g = ctx.createRadialGradient(px - r * 0.35, py - r * 0.38, r * 0.1, px, py, r);
    if (player === BLACK) {
      g.addColorStop(0, "#5b5b5b");
      g.addColorStop(0.45, "#1a1a1a");
      g.addColorStop(1, "#050505");
    } else {
      g.addColorStop(0, "#ffffff");
      g.addColorStop(0.55, "#efe6d4");
      g.addColorStop(1, "#c8b89a");
    }
    ctx.beginPath();
    ctx.arc(px, py, r, 0, Math.PI * 2);
    ctx.fillStyle = g;
    ctx.shadowColor = "rgba(0,0,0,0.35)";
    ctx.shadowBlur = 8;
    ctx.fill();
    ctx.shadowBlur = 0;
    if (marked) {
      ctx.beginPath();
      ctx.arc(px, py, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = "#b43a2c";
      ctx.fill();
    }
    if (number) {
      ctx.fillStyle = player === BLACK ? "#f4ead2" : "#3a2a16";
      ctx.font = `${Math.floor(r)}px "Noto Serif SC", serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(number), px, py + 1);
    }
  }

  function draw(state) {
    pulse += 1;
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    const css = Math.min(640, canvas.clientWidth || 640);
    if (canvas.width !== Math.round(css * dpr)) {
      canvas.width = Math.round(css * dpr);
      canvas.height = Math.round(css * dpr);
    }
    drawWood();
    drawGrid();
    const last = state.moves[state.moves.length - 1];
    const winSet = new Set((state.winLine || []).map(([x, y]) => `${x},${y}`));
    for (let y = 0; y < SIZE; y += 1) {
      for (let x = 0; x < SIZE; x += 1) {
        const v = state.board[y][x];
        if (v === EMPTY) continue;
        const n = state.showNumbers ? state.moveIndex[y][x] : 0;
        const isLast = last && last.x === x && last.y === y;
        drawStone(x, y, v, isLast && !n, winSet.has(`${x},${y}`), n);
      }
    }
    if (hover && state.board[hover[1]][hover[0]] === EMPTY && !state.over && !state.thinking) {
      const [px, py] = point(hover[0], hover[1]);
      ctx.beginPath();
      ctx.arc(px, py, metrics().cell * 0.38, 0, Math.PI * 2);
      ctx.fillStyle = state.human === BLACK ? "rgba(0,0,0,0.18)" : "rgba(255,255,255,0.28)";
      ctx.fill();
    }
  }

  return {
    draw,
    cellAt,
    setHover(pos) {
      hover = pos;
    },
  };
}
