export const SIZE = 15;
export const EMPTY = 0;
export const BLACK = 1;
export const WHITE = 2;

export const DIRS = [
  [1, 0],
  [0, 1],
  [1, 1],
  [1, -1],
];

export function createBoard() {
  return Array.from({ length: SIZE }, () => Array(SIZE).fill(EMPTY));
}

export function inBounds(x, y) {
  return x >= 0 && x < SIZE && y >= 0 && y < SIZE;
}

export function cloneBoard(board) {
  return board.map((row) => row.slice());
}

export function coordLabel(x, y) {
  return `${String.fromCharCode(65 + x)}${y + 1}`;
}

export function checkWin(board, x, y, player) {
  for (const [dx, dy] of DIRS) {
    const line = [[x, y]];
    let nx = x + dx;
    let ny = y + dy;
    while (inBounds(nx, ny) && board[ny][nx] === player) {
      line.push([nx, ny]);
      nx += dx;
      ny += dy;
    }
    nx = x - dx;
    ny = y - dy;
    while (inBounds(nx, ny) && board[ny][nx] === player) {
      line.unshift([nx, ny]);
      nx -= dx;
      ny -= dy;
    }
    if (line.length >= 5) {
      const idx = line.findIndex((p) => p[0] === x && p[1] === y);
      const start = Math.max(0, Math.min(idx - 2, line.length - 5));
      return line.slice(start, start + 5);
    }
  }
  return null;
}

export function isFull(board) {
  return board.every((row) => row.every((cell) => cell !== EMPTY));
}

export function opponent(player) {
  return player === BLACK ? WHITE : BLACK;
}
