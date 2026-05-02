#!/bin/sh
set -eu

docker exec codex sh -lc '/root/.codex/start-deepseek-proxy.sh >/dev/null'
docker exec codex sh -lc 'before=$(wc -l < /root/.codex/log/deepseek-codex-proxy.log 2>/dev/null || echo 0); timeout 180 codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "只回答一句：plain docker codex deepseek ok"; status=$?; after=$(wc -l < /root/.codex/log/deepseek-codex-proxy.log 2>/dev/null || echo 0); echo "codex_status=$status"; echo "proxy_log_lines_before=$before after=$after"; tail -6 /root/.codex/log/deepseek-codex-proxy.log'
