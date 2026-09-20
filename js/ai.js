import {
  SIZE,
  EMPTY,
  BLACK,
  DIRS,
  inBounds,
  opponent,
  checkWin,
} from "./board.js";

export const LEVELS = [
  { id: 1, name: "入门", desc: "信手拈来，适合初学", depth: 0, noise: 0.85, missRate: 0.42, pool: 12 },
  { id: 2, name: "初级", desc: "能攻能守，偶尔漏招", depth: 0, noise: 0.35, missRate: 0.16, pool: 5 },
  { id: 3, name: "中级", desc: "懂得取舍，大局初成", depth: 0, noise: 0.05, missRate: 0, pool: 1 },
  { id: 4, name: "高级", desc: "攻守兼备，算路清晰", depth: 2, noise: 0, missRate: 0, pool: 1, width: 10 },
  { id: 5, name: "大师", desc: "目光深远，步步杀机", depth: 3, noise: 0, missRate: 0, pool: 1, width: 8 },
];

const FIVE = 10_000_000;
const LIVE_FOUR = 100_000;
const RUSH_FOUR = 12_000;
const LIVE_THREE = 8_000;
const SLEEP_THREE = 700;
const LIVE_TWO = 420;
const SLEEP_TWO = 70;
const LIVE_ONE = 18;

function shapeScore(count, openEnds) {
  if (count >= 5) return FIVE;
  if (count === 4) {
    if (openEnds === 2) return LIVE_FOUR;
    if (openEnds === 1) return RUSH_FOUR;
    return 0;
  }
  if (count === 3) {
    if (openEnds === 2) return LIVE_THREE;
    if (openEnds === 1) return SLEEP_THREE;
    return 0;
  }
  if (count === 2) {
    if (openEnds === 2) return LIVE_TWO;
    if (openEnds === 1) return SLEEP_TWO;
    return 0;
  }
  if (count === 1 && openEnds === 2) return LIVE_ONE;
  return 0;
}

function ray(board, x, y, dx, dy, player) {
  let count = 0;
  let nx = x + dx;
  let ny = y + dy;
  while (inBounds(nx, ny) && board[ny][nx] === player) {
    count += 1;
    nx += dx;
    ny += dy;
  }
  const open = inBounds(nx, ny) && board[ny][nx] === EMPTY;
  return { count, open };
}

export function evaluateMove(board, x, y, player) {
  let score = 0;
  for (const [dx, dy] of DIRS) {
    const a = ray(board, x, y, dx, dy, player);
    const b = ray(board, x, y, -dx, -dy, player);
    score += shapeScore(a.count + b.count + 1, (a.open ? 1 : 0) + (b.open ? 1 : 0));
  }
  return score;
}

function compositeScore(board, x, y, me) {
  const attack = evaluateMove(board, x, y, me);
  const defend = evaluateMove(board, x, y, opponent(me));
  return attack * 1.15 + defend;
}

export function getCandidates(board, range = 2) {
  const used = new Set();
  const cells = [];
  let hasStone = false;
  for (let y = 0; y < SIZE; y += 1) {
    for (let x = 0; x < SIZE; x += 1) {
      if (board[y][x] === EMPTY) continue;
      hasStone = true;
      for (let dy = -range; dy <= range; dy += 1) {
        for (let dx = -range; dx <= range; dx += 1) {
          const nx = x + dx;
          const ny = y + dy;
          if (!inBounds(nx, ny) || board[ny][nx] !== EMPTY) continue;
          const key = ny * SIZE + nx;
          if (used.has(key)) continue;
          used.add(key);
          cells.push([nx, ny]);
        }
      }
    }
  }
  if (!hasStone) return [[7, 7]];
  return cells;
}

function rankedMoves(board, me, width) {
  const scored = getCandidates(board).map(([x, y]) => ({
    x,
    y,
    score: compositeScore(board, x, y, me),
  }));
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, width || scored.length);
}

function minimax(board, depth, alpha, beta, me, toMove, width) {
  if (depth === 0) {
    const best = rankedMoves(board, me, 1)[0];
    return { score: (best ? best.score : 0) * (toMove === me ? 1 : -0.85) };
  }
  const moves = rankedMoves(board, toMove, width);
  if (moves.length === 0) return { score: 0 };

  let bestMove = moves[0];
  if (toMove === me) {
    let best = -Infinity;
    for (const move of moves) {
      board[move.y][move.x] = toMove;
      if (checkWin(board, move.x, move.y, toMove)) {
        board[move.y][move.x] = EMPTY;
        return { score: FIVE + depth * 100, move };
      }
      const next = minimax(board, depth - 1, alpha, beta, me, opponent(toMove), width);
      board[move.y][move.x] = EMPTY;
      if (next.score > best) {
        best = next.score;
        bestMove = move;
      }
      alpha = Math.max(alpha, best);
      if (beta <= alpha) break;
    }
    return { score: best, move: bestMove };
  }

  let best = Infinity;
  for (const move of moves) {
    board[move.y][move.x] = toMove;
    if (checkWin(board, move.x, move.y, toMove)) {
      board[move.y][move.x] = EMPTY;
      return { score: -FIVE - depth * 100, move };
    }
    const next = minimax(board, depth - 1, alpha, beta, me, opponent(toMove), width);
    board[move.y][move.x] = EMPTY;
    if (next.score < best) {
      best = next.score;
      bestMove = move;
    }
    beta = Math.min(beta, best);
    if (beta <= alpha) break;
  }
  return { score: best, move: bestMove };
}

function pickFromPool(moves, pool, noise) {
  const top = moves.slice(0, Math.max(1, pool));
  if (noise <= 0) return top[0];
  const weighted = top.map((move, i) => ({
    move,
    weight: Math.max(0.05, (move.score + 1) / (i + 1) * (1 - Math.random() * noise)),
  }));
  weighted.sort((a, b) => b.weight - a.weight);
  return weighted[0].move;
}

export function chooseMove(board, me, level) {
  const cfg = LEVELS.find((item) => item.id === level) || LEVELS[2];
  const moves = rankedMoves(board, me, 24);
  if (moves.length === 0) return null;

  const mustWin = moves.find((m) => m.score >= FIVE * 1.15);
  if (mustWin && cfg.missRate < 0.3) return mustWin;

  const mustBlock = moves.find((m) => evaluateMove(board, m.x, m.y, opponent(me)) >= FIVE);
  if (mustBlock && Math.random() >= cfg.missRate) return mustBlock;

  if (cfg.depth >= 2) {
    const result = minimax(board, cfg.depth, -Infinity, Infinity, me, me, cfg.width);
    return result.move || moves[0];
  }

  if (mustWin) return Math.random() >= cfg.missRate ? mustWin : pickFromPool(moves, cfg.pool, cfg.noise);
  return pickFromPool(moves, cfg.pool, cfg.noise);
}

export function openingBias(board) {
  const stones = board.flat().filter((v) => v !== EMPTY).length;
  if (stones === 0) return { x: 7, y: 7 };
  if (stones === 1 && board[7][7] === BLACK) {
    const around = [
      [8, 7], [6, 7], [7, 8], [7, 6], [8, 8], [6, 6], [8, 6], [6, 8],
    ];
    const [x, y] = around[Math.floor(Math.random() * around.length)];
    return { x, y };
  }
  return null;
}
