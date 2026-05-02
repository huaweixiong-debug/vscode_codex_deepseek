#!/bin/sh
set -eu

docker exec codex sh -lc "ps -eo pid=,args= | grep '[d]eepseek-codex-proxy.js' | awk '{print \$1}' | xargs -r kill 2>/dev/null || true"
sleep 1

docker exec codex sh -lc '/root/.codex/start-deepseek-proxy.sh'
docker exec codex sh -lc 'node -e "fetch(\"http://127.0.0.1:17777/v1/models\").then(r=>r.json()).then(j=>console.log(JSON.stringify(j.data||j.models||j).slice(0,600))).catch(e=>{console.error(e);process.exit(1)})"'
docker exec codex sh -lc 'echo ==codex-debug-models==; codex debug models | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d);process.stdin.on(\"end\",()=>{const j=JSON.parse(s); console.log(j.models.slice(0,5).map(m=>m.slug||m.id).join(\"\n\"));})"'
docker exec codex sh -lc 'echo ==proxy-log==; tail -20 /root/.codex/log/deepseek-codex-proxy.log || true'
