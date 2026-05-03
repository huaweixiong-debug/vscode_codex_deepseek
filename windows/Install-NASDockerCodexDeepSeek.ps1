param(
  [string]$NasHost = "",
  [string]$NasUser = "",
  [int]$SshPort = 22,
  [string]$RemoteCodexDir = "/volume1/docker/codex",
  [string]$ServiceName = "codex",
  [string]$ContainerName = "codex",
  [string]$KeySourceContainer = "",
  [string]$DeepSeekApiKey = "",
  [ValidateSet("openssh", "putty")]
  [string]$SshClient = "openssh",
  [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[NAS Codex DeepSeek] $Message"
}

function Read-Default {
  param(
    [string]$Prompt,
    [string]$Default
  )
  $value = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value.Trim()
}

function Read-SecretLine {
  param([string]$Prompt)
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Shell-SingleQuote {
  param([string]$Value)
  return "'" + ($Value -replace "'", "'\''") + "'"
}

function New-RemoteDeployScript {
@'
#!/bin/sh
set -eu

CODEX_DIR="${CODEX_DIR:-/volume1/docker/codex}"
SERVICE_NAME="${SERVICE_NAME:-codex}"
CONTAINER_NAME="${CONTAINER_NAME:-codex}"
KEY_SOURCE_CONTAINER="${KEY_SOURCE_CONTAINER:-}"
SKIP_SMOKE_TEST="${SKIP_SMOKE_TEST:-0}"
INSTALL_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROXY_SRC="$INSTALL_DIR/deepseek-codex-proxy.js"
KEY_FILE="$INSTALL_DIR/deepseek.env"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

if [ ! -f "$PROXY_SRC" ]; then
  echo "missing proxy source: $PROXY_SRC" >&2
  exit 1
fi

cd "$CODEX_DIR"
if [ ! -f docker-compose.yml ]; then
  echo "docker-compose.yml not found in $CODEX_DIR" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "docker-compose.yml.before-deepseek.$stamp"
[ -f .env ] && cp .env ".env.before-deepseek.$stamp" || true
touch .env

key=""
if [ -f "$KEY_FILE" ]; then
  key="$(sed -n 's/^DEEPSEEK_API_KEY=//p' "$KEY_FILE" | head -n 1)"
fi
if [ -z "$key" ]; then
  key="$(sed -n 's/^DEEPSEEK_API_KEY=//p' .env | head -n 1)"
fi
if [ -z "$key" ] && [ -n "$KEY_SOURCE_CONTAINER" ]; then
  key="$(docker inspect "$KEY_SOURCE_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^DEEPSEEK_API_KEY=//p' | head -n 1 || true)"
fi
if [ -z "$key" ]; then
  echo "DEEPSEEK_API_KEY not found. Provide it interactively or put it in $CODEX_DIR/.env." >&2
  exit 1
fi

if grep -q '^DEEPSEEK_API_KEY=' .env; then
  awk -v key="$key" 'BEGIN{done=0} /^DEEPSEEK_API_KEY=/{print "DEEPSEEK_API_KEY=" key; done=1; next} {print} END{if(!done) print "DEEPSEEK_API_KEY=" key}' .env > .env.tmp
  mv .env.tmp .env
else
  printf '\nDEEPSEEK_API_KEY=%s\n' "$key" >> .env
fi
rm -f "$KEY_FILE"

mkdir -p codex-home/log codex-home/bin
cp "$PROXY_SRC" codex-home/deepseek-codex-proxy.js
chmod 644 codex-home/deepseek-codex-proxy.js

cat > codex-home/start-deepseek-proxy.sh <<'EOF'
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
EOF

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

chmod 700 codex-home/start-deepseek-proxy.sh
chmod 755 codex-home/bin/codex-deepseek

config="codex-home/config.toml"
touch "$config"
cp "$config" "$config.before-deepseek.$stamp"
awk '
BEGIN{skip=0}
/^\[model_providers\.deepseek-codex\]/{skip=1; next}
skip && /^\[/{skip=0}
skip{next}
/^model_provider[[:space:]]*=/{next}
/^model[[:space:]]*=/{next}
/^model_reasoning_effort[[:space:]]*=/{next}
{print}
' "$config" > "$config.body"
cat > "$config" <<'EOF'
model_provider = "deepseek-codex"
model = "deepseek-v4-pro"
model_reasoning_effort = "high"

[model_providers.deepseek-codex]
name = "DeepSeek Codex"
base_url = "http://127.0.0.1:17777/v1"
wire_api = "responses"

EOF
cat "$config.body" >> "$config"
rm -f "$config.body"

if ! grep -q 'DEEPSEEK_API_KEY:' docker-compose.yml; then
  awk '{print} /OPENAI_BASE_URL:/ {print "      DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY:-}"}' docker-compose.yml > docker-compose.yml.tmp
  mv docker-compose.yml.tmp docker-compose.yml
fi

if ! grep -q './codex-home/bin/codex-deepseek:/usr/local/bin/codex-deepseek:ro' docker-compose.yml; then
  awk '{print} /- \.\/codex-home:\/root\/\.codex/ {print "      - ./codex-home/bin/codex-deepseek:/usr/local/bin/codex-deepseek:ro"}' docker-compose.yml > docker-compose.yml.tmp
  mv docker-compose.yml.tmp docker-compose.yml
fi

awk '
/^[[:space:]]*command:[[:space:]]*\["sleep",[[:space:]]*"infinity"\]/ {
  print "    command: [\"sh\", \"-lc\", \"/root/.codex/start-deepseek-proxy.sh || true; exec sleep infinity\"]"
  next
}
{ print }
' docker-compose.yml > docker-compose.yml.tmp
mv docker-compose.yml.tmp docker-compose.yml

if ! docker compose up -d "$SERVICE_NAME"; then
  echo "docker compose up failed. Trying container-name conflict recovery..." >&2
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rename "$CONTAINER_NAME" "$CONTAINER_NAME.before-deepseek.$stamp"
    docker compose up -d "$SERVICE_NAME"
  else
    exit 1
  fi
fi

docker exec "$CONTAINER_NAME" sh -lc '/root/.codex/start-deepseek-proxy.sh'
docker exec "$CONTAINER_NAME" sh -lc 'sed -n "1,40p" /root/.codex/config.toml'

if [ "$SKIP_SMOKE_TEST" != "1" ]; then
  docker exec "$CONTAINER_NAME" sh -lc 'before=$(wc -l < /root/.codex/log/deepseek-codex-proxy.log 2>/dev/null || echo 0); timeout 180 codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "只回答一句：nas docker codex deepseek ok"; status=$?; after=$(wc -l < /root/.codex/log/deepseek-codex-proxy.log 2>/dev/null || echo 0); echo "codex_status=$status"; echo "proxy_log_lines_before=$before after=$after"; tail -8 /root/.codex/log/deepseek-codex-proxy.log'
fi

echo "NAS Docker Codex DeepSeek deployment completed."
'@
}

while (-not $NasHost) { $NasHost = (Read-Host "NAS SSH host/IP").Trim() }
if (-not $NasUser) { $NasUser = Read-Host "NAS SSH username" }
if (-not $NasUser) { throw "NAS SSH username is required." }
$SshPort = [int](Read-Default "SSH port" ([string]$SshPort))
$RemoteCodexDir = Read-Default "Remote codex compose directory" $RemoteCodexDir
$ServiceName = Read-Default "Docker compose service name" $ServiceName
$ContainerName = Read-Default "Docker container name" $ContainerName

if (-not $DeepSeekApiKey) {
  Write-Host ""
  Write-Host "DeepSeek API key source:"
  Write-Host "  1. Enter key now"
  Write-Host "  2. Reuse remote $RemoteCodexDir/.env"
  Write-Host "  3. Copy from another Docker container env"
  $choice = Read-Default "Choose" "3"
  if ($choice -eq "1") {
    $DeepSeekApiKey = Read-SecretLine "Enter DEEPSEEK_API_KEY"
  } elseif ($choice -eq "3") {
    $KeySourceContainer = Read-Default "Container that already has DEEPSEEK_API_KEY" "hermes"
  }
}

Write-Host ""
Write-Host "SSH client:"
Write-Host "  1. openssh: ssh/scp, may prompt for password several times"
Write-Host "  2. putty: plink/pscp, can prompt for or pass password"
$clientChoice = Read-Default "Choose" ($(if ($SshClient -eq "putty") { "2" } else { "1" }))
if ($clientChoice -eq "2") { $SshClient = "putty" } else { $SshClient = "openssh" }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ProxySource = Join-Path $RepoRoot "deepseek-codex-proxy.js"
if (-not (Test-Path -LiteralPath $ProxySource)) {
  throw "Missing proxy source: $ProxySource"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("codex-deepseek-nas-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$remoteScript = Join-Path $temp "install-nas-codex-deepseek-remote.sh"
$remoteProxy = Join-Path $temp "deepseek-codex-proxy.js"
Set-Content -LiteralPath $remoteScript -Value (New-RemoteDeployScript) -Encoding UTF8
Copy-Item -LiteralPath $ProxySource -Destination $remoteProxy -Force

if ($DeepSeekApiKey) {
  Set-Content -LiteralPath (Join-Path $temp "deepseek.env") -Value "DEEPSEEK_API_KEY=$DeepSeekApiKey" -Encoding ASCII
}

$remoteDir = "~/.codex-deepseek-install-" + (Get-Date -Format "yyyyMMddHHmmss")
$remote = "$NasUser@$NasHost"

try {
  if ($SshClient -eq "putty") {
    $plink = (Get-Command plink.exe -ErrorAction Stop).Source
    $pscp = (Get-Command pscp.exe -ErrorAction Stop).Source
    $puttyPassword = Read-SecretLine "NAS SSH password for PuTTY mode"

    $baseArgs = @("-P", "$SshPort", "-pw", $puttyPassword)
    & $plink @baseArgs $remote "mkdir -p $remoteDir"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create remote install dir." }

    $copyArgs = @("-scp", "-P", "$SshPort", "-pw", $puttyPassword, $remoteScript, $remoteProxy)
    if (Test-Path -LiteralPath (Join-Path $temp "deepseek.env")) {
      $copyArgs += (Join-Path $temp "deepseek.env")
    }
    $copyArgs += "${remote}:$remoteDir/"
    & $pscp @copyArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy install files." }

    $remoteCommand = "cd $remoteDir && chmod 700 install-nas-codex-deepseek-remote.sh && CODEX_DIR=$(Shell-SingleQuote $RemoteCodexDir) SERVICE_NAME=$(Shell-SingleQuote $ServiceName) CONTAINER_NAME=$(Shell-SingleQuote $ContainerName) KEY_SOURCE_CONTAINER=$(Shell-SingleQuote $KeySourceContainer) SKIP_SMOKE_TEST=$(if ($SkipSmokeTest) { "1" } else { "0" }) ./install-nas-codex-deepseek-remote.sh"
    & $plink @baseArgs $remote $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote deployment failed." }
  } else {
    $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    $scp = (Get-Command scp.exe -ErrorAction Stop).Source

    & $ssh -p $SshPort $remote "mkdir -p $remoteDir"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create remote install dir." }

    $files = @($remoteScript, $remoteProxy)
    if (Test-Path -LiteralPath (Join-Path $temp "deepseek.env")) {
      $files += (Join-Path $temp "deepseek.env")
    }
    & $scp -P $SshPort @files "${remote}:$remoteDir/"
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy install files." }

    $remoteCommand = "cd $remoteDir && chmod 700 install-nas-codex-deepseek-remote.sh && CODEX_DIR=$(Shell-SingleQuote $RemoteCodexDir) SERVICE_NAME=$(Shell-SingleQuote $ServiceName) CONTAINER_NAME=$(Shell-SingleQuote $ContainerName) KEY_SOURCE_CONTAINER=$(Shell-SingleQuote $KeySourceContainer) SKIP_SMOKE_TEST=$(if ($SkipSmokeTest) { "1" } else { "0" }) ./install-nas-codex-deepseek-remote.sh"
    & $ssh -p $SshPort $remote $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote deployment failed." }
  }
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "Done"
