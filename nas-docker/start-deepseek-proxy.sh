#!/bin/sh
set -eu

PORT="${CODEX_DEEPSEEK_PORT:-17777}"
LOG_DIR="${CODEX_DEEPSEEK_LOG_DIR:-/root/.codex/log}"
PROXY="/root/.codex/deepseek-codex-proxy.js"

mkdir -p "$LOG_DIR"

if node -e "const net=require('net'); const s=net.connect($PORT,'127.0.0.1'); s.on('connect',()=>process.exit(0)); s.on('error',()=>process.exit(1)); setTimeout(()=>process.exit(1),500);" >/dev/null 2>&1; then
  echo "DeepSeek Codex proxy already running at http://127.0.0.1:$PORT/v1"
  exit 0
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "DEEPSEEK_API_KEY is not set in the container environment" >&2
  exit 1
fi

PORT="$PORT" CODEX_DEEPSEEK_LOG_DIR="$LOG_DIR" nohup node "$PROXY" >"$LOG_DIR/deepseek-codex-proxy.stdout.log" 2>"$LOG_DIR/deepseek-codex-proxy.stderr.log" &
echo $! > /root/.codex/deepseek-codex-proxy.pid
sleep 1

node -e "const net=require('net'); const s=net.connect($PORT,'127.0.0.1'); s.on('connect',()=>process.exit(0)); s.on('error',()=>process.exit(1)); setTimeout(()=>process.exit(1),1000);"
echo "DeepSeek Codex proxy started at http://127.0.0.1:$PORT/v1"
