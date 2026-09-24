#!/usr/bin/env bash
# =============================================================================
# 瑞学五子棋 Ubuntu HTTPS 启动脚本（只占用 8003，不占用 80）
# =============================================================================
# 证书用 acme.sh TLS-ALPN 在 443 上验证，验证时短暂监听 443，不改 Nginx、不碰 80。
# 浏览器请打开：https://服务器IP:8003
#
#   bash start.sh --daemon      后台启动
#   bash start.sh --stop        停止
#   bash start.sh --status      状态
#   bash start.sh --issue-le    申请/续签 Let's Encrypt IP 证书后启动
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8003}"
HOST="${HOST:-0.0.0.0}"
INDEX="$ROOT/index.html"
SERVE_PY="$ROOT/serve.py"
LOG_DIR="$ROOT/logs"
PID_FILE="$ROOT/rxgobang.pid"
LOG_FILE="$LOG_DIR/rxgobang.log"
CERT_DIR="$ROOT/certs"
CERT_FILE="${SSL_CERT:-$CERT_DIR/server.crt}"
KEY_FILE="${SSL_KEY:-$CERT_DIR/server.key}"
ACME_HOME="${ACME_HOME:-/root/.acme.sh}"
DAEMON=0
ACTION="start"

for arg in "$@"; do
  case "$arg" in
    --daemon|-d) DAEMON=1 ;;
    --stop) ACTION="stop" ;;
    --status) ACTION="status" ;;
    --issue-le) ACTION="issue-le" ;;
    --help|-h)
      echo "Usage: $0 [--daemon] [--stop] [--status] [--issue-le]"
      echo "  HTTPS on ${PORT} only. ACME uses 443, never port 80."
      exit 0
      ;;
    *)
      echo "[error] unknown arg: $arg"
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

stop_server() {
  if is_running; then
    local pid
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
}

detect_public_ip() {
  if [[ -n "${CERT_IP:-}" ]]; then
    echo "$CERT_IP"
    return
  fi
  local ip=""
  ip="$(curl -4 -fsS --max-time 3 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null || true)"
  fi
  ip="$(echo "$ip" | tr -d '[:space:]')"
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "127.0.0.1"
    return
  fi
  echo "$ip"
}

public_url() {
  echo "https://$(detect_public_ip):${PORT}"
}

acme_bin() {
  if [[ -x "$ACME_HOME/acme.sh" ]]; then
    echo "$ACME_HOME/acme.sh"
    return 0
  fi
  if command -v acme.sh >/dev/null 2>&1; then
    command -v acme.sh
    return 0
  fi
  return 1
}

ensure_acme() {
  if acme_bin >/dev/null; then
    return 0
  fi
  echo "[info] installing acme.sh ..."
  if ! command -v curl >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl
  fi
  curl https://get.acme.sh | sh -s email=rxgobang.acme@gmail.com
  if [[ -x "$ACME_HOME/acme.sh" ]]; then
    "$ACME_HOME/acme.sh" --register-account -m rxgobang.acme@gmail.com >/dev/null 2>&1 || true
  fi
}

open_443() {
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi
}

assert_443_free() {
  if ss -lnt | awk '{print $4}' | grep -qE '(:443)$'; then
    echo "[error] 443 已被占用，TLS-ALPN 无法申请证书，且按约定不能改用 80。"
    ss -lntp | grep ':443' || true
    exit 1
  fi
}

issue_letsencrypt() {
  local ip
  ip="$(detect_public_ip)"
  if [[ "$ip" == "127.0.0.1" ]]; then
    echo "[error] 无法检测公网 IP，请设置 CERT_IP=x.x.x.x"
    exit 1
  fi
  echo "[info] issuing Let's Encrypt IP cert via TLS-ALPN on :443  ip=$ip"
  echo "[info] will not bind or change port 80"

  ensure_acme
  open_443
  assert_443_free

  local acme
  acme="$(acme_bin)"
  "$acme" --register-account -m rxgobang.acme@gmail.com >/dev/null 2>&1 || true
  mkdir -p "$CERT_DIR"

  local reload_cmd
  reload_cmd="sed -i 's/\\r\$//' '$ROOT/start.sh' '$ROOT/serve.py' 2>/dev/null || true; bash '$ROOT/start.sh' --stop >/dev/null 2>&1 || true; bash '$ROOT/start.sh' --daemon"

  set +e
  "$acme" --issue --server letsencrypt --alpn \
    -d "$ip" \
    -m rxgobang.acme@gmail.com \
    --certificate-profile shortlived \
    --days 3
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "[info] retry with --cert-profile ..."
    "$acme" --issue --server letsencrypt --alpn \
      -d "$ip" \
      -m rxgobang.acme@gmail.com \
      --cert-profile shortlived \
      --days 3
    rc=$?
  fi
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "[error] acme.sh TLS-ALPN 签发失败。"
    echo "        请确认云安全组放行入站 TCP 443（只用于申请/续期，网站仍在 8003）。"
    echo "        不会改 80 端口。"
    exit 1
  fi

  "$acme" --install-cert -d "$ip" \
    --fullchain-file "$CERT_FILE" \
    --key-file "$KEY_FILE" \
    --reloadcmd "$reload_cmd"

  chmod 644 "$CERT_FILE"
  chmod 600 "$KEY_FILE"
  echo "[info] cert installed: $CERT_FILE"
}

ensure_cert() {
  if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
    return 0
  fi
  echo "[error] missing TLS cert: $CERT_FILE"
  echo "        run: CERT_IP=公网IP bash $ROOT/start.sh --issue-le"
  exit 1
}

start_https() {
  cd "$ROOT"
  if [[ ! -f "$INDEX" ]]; then
    echo "[error] missing $INDEX"
    exit 1
  fi
  if [[ ! -f "$SERVE_PY" ]]; then
    echo "[error] missing $SERVE_PY"
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[error] python3 not found"
    exit 1
  fi
  sed -i 's/\r$//' "$SERVE_PY" "$ROOT/start.sh" 2>/dev/null || true
  ensure_cert
  mkdir -p "$LOG_DIR"
  echo "[info] starting $(public_url)/"
  echo "[info] cert=$CERT_FILE"

  if [[ "$DAEMON" -eq 1 ]]; then
    nohup python3 "$SERVE_PY" \
      --bind "$HOST" \
      --port "$PORT" \
      --directory "$ROOT" \
      --cert "$CERT_FILE" \
      --key "$KEY_FILE" \
      >>"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    sleep 0.8
    if is_running; then
      echo "[info] started in background pid=$(cat "$PID_FILE")"
      echo "[info] log: $LOG_FILE"
    else
      echo "[error] start failed, see log: $LOG_FILE"
      rm -f "$PID_FILE"
      exit 1
    fi
  else
    exec python3 "$SERVE_PY" \
      --bind "$HOST" \
      --port "$PORT" \
      --directory "$ROOT" \
      --cert "$CERT_FILE" \
      --key "$KEY_FILE"
  fi
}

if [[ "$ACTION" == "stop" ]]; then
  stop_server
  exit 0
fi

if [[ "$ACTION" == "status" ]]; then
  if is_running; then
    echo "[info] running pid=$(cat "$PID_FILE")  $(public_url)/"
    exit 0
  fi
  echo "[info] not running"
  exit 1
fi

if [[ "$ACTION" == "issue-le" ]]; then
  issue_letsencrypt
  if is_running; then
    stop_server
  fi
  DAEMON=1
fi

if is_running; then
  echo "[error] already running pid=$(cat "$PID_FILE"). Stop first: bash $ROOT/start.sh --stop"
  exit 1
fi

start_https
