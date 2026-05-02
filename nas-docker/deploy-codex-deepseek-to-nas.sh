#!/bin/sh
set -eu

docker cp "$HOME/nas-update-codex-config.js" codex:/tmp/nas-update-codex-config.js
docker cp "$HOME/start-deepseek-proxy.docker.sh" codex:/root/.codex/start-deepseek-proxy.sh
docker cp "$HOME/codex-deepseek.docker.sh" codex:/usr/local/bin/codex-deepseek

docker exec codex sh -lc 'node /tmp/nas-update-codex-config.js'
docker exec codex sh -lc 'chown root:root /root/.codex/start-deepseek-proxy.sh /usr/local/bin/codex-deepseek /root/.codex/config.toml'
docker exec codex sh -lc 'chmod 700 /root/.codex/start-deepseek-proxy.sh && chmod 755 /usr/local/bin/codex-deepseek'

docker exec codex sh -lc 'sed -n "1,100p" /root/.codex/config.toml'
docker exec codex sh -lc 'echo ==scripts== && ls -l /root/.codex/start-deepseek-proxy.sh /usr/local/bin/codex-deepseek'
