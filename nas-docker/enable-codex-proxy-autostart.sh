#!/bin/sh
set -eu

cd /volume1/docker/codex
stamp="$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "docker-compose.yml.before-proxy-autostart.$stamp"

awk '
  /^[[:space:]]*command:[[:space:]]*\["sleep",[[:space:]]*"infinity"\]/ {
    print "    command: [\"sh\", \"-lc\", \"/root/.codex/start-deepseek-proxy.sh || true; exec sleep infinity\"]"
    next
  }
  { print }
' docker-compose.yml > docker-compose.yml.tmp
mv docker-compose.yml.tmp docker-compose.yml

sed -n '1,120p' docker-compose.yml | sed -E 's/(KEY|TOKEN|SECRET|PASSWORD|API_KEY):.*/\1: ***masked***/I'
