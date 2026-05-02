#!/bin/sh
set -eu

cd /volume1/docker/codex
stamp="$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "docker-compose.yml.before-wrapper-mount.$stamp"

mkdir -p codex-home/bin
cat > codex-home/bin/codex-deepseek <<'EOF'
#!/bin/sh
set -eu

/root/.codex/start-deepseek-proxy.sh >/dev/null
export CODEX_OSS_BASE_URL="http://127.0.0.1:${CODEX_DEEPSEEK_PORT:-17777}/v1"

exec codex \
  -c 'model_provider="deepseek-codex"' \
  -c 'model="deepseek-v4-pro"' \
  "$@"
EOF
chmod 755 codex-home/bin/codex-deepseek

if ! grep -q './codex-home/bin/codex-deepseek:/usr/local/bin/codex-deepseek:ro' docker-compose.yml; then
  awk '{print} /- \.\/codex-home:\/root\/\.codex/ {print "      - ./codex-home/bin/codex-deepseek:/usr/local/bin/codex-deepseek:ro"}' docker-compose.yml > docker-compose.yml.tmp
  mv docker-compose.yml.tmp docker-compose.yml
fi

sed -n '1,120p' docker-compose.yml | sed -E 's/(KEY|TOKEN|SECRET|PASSWORD|API_KEY):.*/\1: ***masked***/I'
