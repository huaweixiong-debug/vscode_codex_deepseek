#!/bin/sh
set -eu

/root/.codex/start-deepseek-proxy.sh >/dev/null
export CODEX_OSS_BASE_URL="http://127.0.0.1:${CODEX_DEEPSEEK_PORT:-17777}/v1"

exec codex \
  -c 'model_provider="deepseek-codex"' \
  -c 'model="deepseek-v4-pro"' \
  "$@"
