#!/usr/bin/env bash
# =============================================================================
# deploy.sh — 从本机一键发布到 Ubuntu / 宝塔
# =============================================================================
# 用法（在项目根目录）：
#   bash deploy.sh              发布静态页 + 重启 + 检查
#   bash deploy.sh --dry-run    只看会同步哪些文件，不真正上传
#   bash deploy.sh --setup-key  把本机 SSH 公钥装到服务器，以后免密
#   bash deploy.sh --skip-restart  只传文件，不重启进程
#
# 配置：复制 deploy.env.example 为 deploy.env 后填写主机和密码。
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DRY_RUN=0
SETUP_KEY=0
SKIP_RESTART=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --setup-key) SETUP_KEY=1 ;;
    --skip-restart) SKIP_RESTART=1 ;;
    --help|-h)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "[error] unknown arg: $arg  (use --help)"
      exit 1
      ;;
  esac
done

load_env() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    local key="${line%%=*}"
    local val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val#\"}"
    val="${val%\"}"
    val="${val#\'}"
    val="${val%\'}"
    export "$key=$val"
  done < "$file"
}

load_env "$ROOT/deploy.env"

DEPLOY_HOST="${DEPLOY_HOST:-47.97.245.103}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/www/wwwroot/RxGobang8003}"
DEPLOY_SSH_PORT="${DEPLOY_SSH_PORT:-22}"
APP_PORT="${APP_PORT:-8003}"
DEPLOY_PASS="${DEPLOY_PASS:-}"

REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}"
SITE_URL="https://${DEPLOY_HOST}:${APP_PORT}/"

echo "[info] target  ${REMOTE}:${DEPLOY_SSH_PORT}"
echo "[info] path    ${DEPLOY_PATH}"
echo "[info] url     ${SITE_URL}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[error] 找不到命令: $1"
    exit 1
  }
}

need_cmd ssh
need_cmd tar

ASKPASS_FILE=""
cleanup() {
  if [[ -n "$ASKPASS_FILE" && -f "$ASKPASS_FILE" ]]; then
    rm -f "$ASKPASS_FILE"
  fi
}
trap cleanup EXIT

SSH_BASE=(
  -p "$DEPLOY_SSH_PORT"
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=30
  -o ConnectTimeout=12
)

SSH_PREFIX=()

if [[ "$DRY_RUN" -eq 0 ]]; then
  if ssh "${SSH_BASE[@]}" -o BatchMode=yes -o ConnectTimeout=8 "$REMOTE" "true" >/dev/null 2>&1; then
    echo "[info] SSH 密钥登录成功"
  else
    if [[ -z "$DEPLOY_PASS" ]]; then
      echo "[error] 密钥登录失败，且 deploy.env 里没有 DEPLOY_PASS"
      echo "        请填写密码，或先执行: bash deploy.sh --setup-key"
      exit 1
    fi
    if command -v sshpass >/dev/null 2>&1; then
      export SSHPASS="$DEPLOY_PASS"
      SSH_PREFIX=(sshpass -e)
      SSH_BASE+=(-o PreferredAuthentications=password -o PubkeyAuthentication=no)
      echo "[info] 使用 sshpass 密码登录"
    else
      ASKPASS_FILE="$(mktemp)"
      umask 077
      printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$DEPLOY_PASS" > "$ASKPASS_FILE"
      chmod 700 "$ASKPASS_FILE"
      export SSH_ASKPASS="$ASKPASS_FILE"
      export SSH_ASKPASS_REQUIRE=force
      export DISPLAY="${DISPLAY:-:0}"
      SSH_BASE+=(-o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
      echo "[info] 使用 SSH_ASKPASS 密码登录（建议安装 sshpass 或改用 --setup-key）"
    fi
  fi
fi

ssh_run() {
  "${SSH_PREFIX[@]}" ssh "${SSH_BASE[@]}" "$REMOTE" "$@"
}

if [[ "$SETUP_KEY" -eq 1 ]]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  local_key="$HOME/.ssh/id_ed25519"
  if [[ ! -f "${local_key}.pub" ]]; then
    echo "[info] 生成本机 SSH 密钥: $local_key"
    ssh-keygen -t ed25519 -N "" -f "$local_key"
  fi
  echo "[info] 安装公钥到 ${REMOTE}:~/.ssh/authorized_keys"
  pub="$(cat "${local_key}.pub")"
  ssh_run "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys"
  echo "[info] 完成。之后可把 deploy.env 里的 DEPLOY_PASS 删掉。"
  exit 0
fi

if [[ ! -f "$ROOT/index.html" ]]; then
  echo "[error] 找不到 index.html"
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"; cleanup' EXIT

if [[ ! -f "$ROOT/serve.py" ]]; then
  echo "[error] 找不到 serve.py"
  exit 1
fi

cp "$ROOT/index.html" "$STAGE/index.html"
cp "$ROOT/start.sh" "$STAGE/start.sh"
cp "$ROOT/serve.py" "$STAGE/serve.py"
if [[ -f "$ROOT/rxgobang.service" ]]; then
  cp "$ROOT/rxgobang.service" "$STAGE/rxgobang.service"
fi
cp -R "$ROOT/css" "$STAGE/css"
cp -R "$ROOT/js" "$STAGE/js"
rm -f "$STAGE/js/pwa.js"
mkdir -p "$STAGE/icons"
find "$ROOT/icons" -maxdepth 1 -type f -name '*.png' ! -name 'icon-source.png' -exec cp {} "$STAGE/icons/" \;

echo "[info] 将上传: start.sh, serve.py, index.html, css/, js/, icons/"
echo "[info] 不会上传: deploy.env, .git, logs, certs"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] 暂存目录文件："
  (cd "$STAGE" && find . -type f | sort)
  echo "[dry-run] 未连接服务器，退出"
  exit 0
fi

echo "[info] 确保远程目录存在 ..."
ssh_run "mkdir -p '$DEPLOY_PATH'"

if command -v rsync >/dev/null 2>&1; then
  echo "[info] rsync 同步 ..."
  rsync -az --delete \
    --exclude='logs/' \
    --exclude='certs/' \
    --exclude='*.pid' \
    --exclude='deploy.env' \
    -e "ssh -p ${DEPLOY_SSH_PORT} -o StrictHostKeyChecking=accept-new" \
    "$STAGE/" "$REMOTE:$DEPLOY_PATH/"
else
  echo "[info] 本机没有 rsync，改用 tar + ssh ..."
  tar -C "$STAGE" -czf - . | ssh_run "tar -xzf - -C '$DEPLOY_PATH'"
fi

echo "[info] 修复脚本换行符 ..."
ssh_run "sed -i 's/\r$//' '$DEPLOY_PATH/start.sh' '$DEPLOY_PATH/serve.py' && chmod +x '$DEPLOY_PATH/start.sh' '$DEPLOY_PATH/serve.py' && rm -f '$DEPLOY_PATH/sw.js' '$DEPLOY_PATH/manifest.json' '$DEPLOY_PATH/js/pwa.js'"

if [[ "$SKIP_RESTART" -eq 1 ]]; then
  echo "[info] 已跳过重启。文件已上传到 $DEPLOY_PATH"
  exit 0
fi

echo "[info] 检查远程 Python / curl ..."
ssh_run "command -v python3 >/dev/null && command -v curl >/dev/null || (export DEBIAN_FRONTEND=noninteractive && apt-get update -y && apt-get install -y python3 curl)"

echo "[info] 重启服务 ..."
ssh_run "bash '$DEPLOY_PATH/start.sh' --stop >/dev/null 2>&1 || true; if [[ -f '$DEPLOY_PATH/certs/server.crt' && -f '$DEPLOY_PATH/certs/server.key' ]]; then CERT_IP='${DEPLOY_HOST}' bash '$DEPLOY_PATH/start.sh' --daemon; else CERT_IP='${DEPLOY_HOST}' bash '$DEPLOY_PATH/start.sh' --issue-le; fi"

echo "[info] 检查防火墙是否放行 ${APP_PORT} 和 443（443 仅用于证书续期） ..."
ssh_run "command -v ufw >/dev/null 2>&1 && ufw allow ${APP_PORT}/tcp && ufw allow 443/tcp || true"

echo "[info] 等待进程起来 ..."
health_py="import ssl,urllib.request; ctx=ssl._create_unverified_context(); urllib.request.urlopen('https://127.0.0.1:${APP_PORT}/', context=ctx, timeout=3).read(32)"
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ssh_run "python3 -c \"$health_py\"" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 1
done

if [[ "$ok" -ne 1 ]]; then
  echo "[error] 健康检查失败。最近日志："
  ssh_run "tail -n 40 '$DEPLOY_PATH/logs/rxgobang.log' 2>/dev/null || echo '(没有日志文件)'"
  exit 1
fi

echo "[done] 部署完成  $SITE_URL"
ssh_run "bash '$DEPLOY_PATH/start.sh' --status" || true
