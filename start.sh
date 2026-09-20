#!/usr/bin/env bash
# =============================================================================
# 瑞学五子棋 Ubuntu / 宝塔 启动脚本
# =============================================================================
# 这个文件只能在 Linux（Ubuntu、宝塔面板那台云服务器）上用。
# 本项目是静态网页，用 Python 内置 http.server 提供页面，不需要 Node / venv。
#
# 【第一次使用前】在服务器执行：
#   apt update
#   apt install -y python3 unzip
#
# 【单独启动命令】（文件已放到 /www/wwwroot/RxGobang8003 之后）
#   bash /www/wwwroot/RxGobang8003/start.sh --daemon
#
# 【以后更新】Windows 执行 deploy.ps1 后会自动覆盖并重启。手动更新则：
#   bash /www/wwwroot/RxGobang8003/start.sh --stop
#   unzip -o /www/wwwroot/RxGobang-deploy.zip -d /www/wwwroot/RxGobang8003
#   sed -i 's/\r$//' /www/wwwroot/RxGobang8003/start.sh
#   bash /www/wwwroot/RxGobang8003/start.sh --daemon
#
# 【常用参数】
#   bash start.sh                 前台运行，Ctrl+C 停止；关掉 SSH 也会停
#   bash start.sh --daemon        后台运行，关掉 SSH 也继续（生产常用）
#   bash start.sh --stop          停止后台进程
#   bash start.sh --status        查看是否在运行
#
# 启动成功后浏览器打开：http://服务器IP:8003
# 宝塔防火墙 / 云服务器安全组都要放行 8003 端口。
#
# 【Windows 上传后必做】脚本可能带 Windows 换行符 \r，Linux 会报错。先执行：
#   sed -i 's/\r$//' /www/wwwroot/RxGobang8003/start.sh
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8003}"
HOST="${HOST:-0.0.0.0}"
INDEX="$ROOT/index.html"
LOG_DIR="$ROOT/logs"
PID_FILE="$ROOT/rxgobang.pid"
LOG_FILE="$LOG_DIR/rxgobang.log"
DAEMON=0
ACTION="start"

for arg in "$@"; do
  case "$arg" in
    --daemon|-d) DAEMON=1 ;;
    --stop) ACTION="stop" ;;
    --status) ACTION="status" ;;
    --help|-h)
      echo "Usage: $0 [--daemon] [--stop] [--status]"
      echo "  default port 8003, listen 0.0.0.0"
      echo "  PORT=8003 HOST=0.0.0.0 $0 --daemon"
      exit 0
      ;;
    *)
      echo "[error] unknown arg: $arg"
      echo "use --help"
      exit 1
      ;;
  esac
done

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

if [[ "$ACTION" == "stop" ]]; then
  if is_running; then
    pid="$(cat "$PID_FILE")"
    echo "[info] stopping pid=$pid ..."
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.4
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    echo "[info] stopped"
  else
    rm -f "$PID_FILE"
    echo "[info] not running"
  fi
  exit 0
fi

if [[ "$ACTION" == "status" ]]; then
  if is_running; then
    pid="$(cat "$PID_FILE")"
    echo "[info] running pid=$pid  http://${HOST}:${PORT}"
    exit 0
  fi
  echo "[info] not running"
  exit 1
fi

cd "$ROOT"

if is_running; then
  pid="$(cat "$PID_FILE")"
  echo "[error] already running pid=$pid . Stop first: bash $ROOT/start.sh --stop"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] python3 not found. Install:"
  echo "  apt install -y python3"
  exit 1
fi

if [[ ! -f "$INDEX" ]]; then
  echo "[error] missing $INDEX"
  echo "  Re-pack on Windows with deploy.ps1, then upload again."
  exit 1
fi

mkdir -p "$LOG_DIR"

echo "[info] starting http://${HOST}:${PORT}"

if [[ "$DAEMON" -eq 1 ]]; then
  nohup python3 -m http.server "$PORT" --bind "$HOST" --directory "$ROOT" \
    >>"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 0.8
  if is_running; then
    echo "[info] started in background pid=$(cat "$PID_FILE")"
    echo "[info] log: $LOG_FILE"
    echo "[info] stop: bash $ROOT/start.sh --stop"
  else
    echo "[error] start failed, see log: $LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
  fi
else
  exec python3 -m http.server "$PORT" --bind "$HOST" --directory "$ROOT"
fi
