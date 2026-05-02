#!/bin/sh
set -eu

cd /volume1/docker/codex
stamp="$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "docker-compose.yml.before-deepseek.$stamp"
cp .env ".env.before-deepseek.$stamp"

key="$(docker inspect hermes --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^DEEPSEEK_API_KEY=//p' | head -n 1)"
if [ -z "$key" ]; then
  echo "missing hermes DEEPSEEK_API_KEY" >&2
  exit 1
fi

if grep -q '^DEEPSEEK_API_KEY=' .env; then
  awk -v key="$key" 'BEGIN{done=0} /^DEEPSEEK_API_KEY=/{print "DEEPSEEK_API_KEY=" key; done=1; next} {print} END{if(!done) print "DEEPSEEK_API_KEY=" key}' .env > .env.tmp
  mv .env.tmp .env
else
  printf '\nDEEPSEEK_API_KEY=%s\n' "$key" >> .env
fi

if ! grep -q 'DEEPSEEK_API_KEY:' docker-compose.yml; then
  awk '{print} /OPENAI_BASE_URL:/ {print "      DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY:-}"}' docker-compose.yml > docker-compose.yml.tmp
  mv docker-compose.yml.tmp docker-compose.yml
fi

echo "==compose-env-lines=="
sed -n '1,90p' docker-compose.yml | sed -E 's/(KEY|TOKEN|SECRET|PASSWORD|API_KEY):.*/\1: ***masked***/I'
echo "==env-lines=="
sed -n '1,140p' .env | sed -E 's/^([^#=]*(KEY|TOKEN|SECRET|PASSWORD|API)[^=]*)=.*/\1=***masked***/I'
