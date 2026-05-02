param(
  [string]$Workspace = "D:\Claude",
  [switch]$App,
  [switch]$ProxyOnly
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProxyScript = Join-Path $Root "deepseek-codex-proxy.js"
$LogDir = Join-Path $env:USERPROFILE ".codex\log"
$SecretFile = Join-Path $env:USERPROFILE ".codex\deepseek.env"
$Port = 17777

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-DeepSeekKey {
  if ($env:DEEPSEEK_API_KEY) {
    return $env:DEEPSEEK_API_KEY
  }
  if (Test-Path -LiteralPath $SecretFile) {
    foreach ($line in Get-Content -LiteralPath $SecretFile) {
      if ($line -match '^\s*DEEPSEEK_API_KEY\s*=\s*(.+?)\s*$') {
        return $Matches[1].Trim().Trim('"').Trim("'")
      }
    }
  }
  throw "DEEPSEEK_API_KEY not found. Set it in the environment or in $SecretFile."
}

function Test-PortOpen {
  param([int]$Port)
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $task = $client.ConnectAsync("127.0.0.1", $Port)
    if (-not $task.Wait(500)) {
      return $false
    }
    return $client.Connected
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

$env:DEEPSEEK_API_KEY = Get-DeepSeekKey

if (-not (Test-Path -LiteralPath $ProxyScript)) {
  throw "Missing proxy script: $ProxyScript"
}

if (-not (Test-PortOpen -Port $Port)) {
  $stdout = Join-Path $LogDir "deepseek-codex-proxy.stdout.log"
  $stderr = Join-Path $LogDir "deepseek-codex-proxy.stderr.log"
  $env:PORT = [string]$Port
  $env:CODEX_DEEPSEEK_LOG_DIR = $LogDir
  Start-Process -FilePath "node" -ArgumentList "`"$ProxyScript`"" -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null
  Start-Sleep -Seconds 1
}

if (-not (Test-PortOpen -Port $Port)) {
  throw "DeepSeek Codex proxy did not start on 127.0.0.1:$Port."
}

$env:CODEX_OSS_BASE_URL = "http://127.0.0.1:$Port/v1"

if ($ProxyOnly) {
  Write-Host "DeepSeek Codex proxy is running at $env:CODEX_OSS_BASE_URL"
  exit 0
}

if ($App) {
  & codex app `
    -c 'model_provider="lmstudio"' `
    -c 'model="deepseek-v4-pro"' `
    -c 'model_providers.lmstudio.base_url="http://127.0.0.1:17777/v1"' `
    -c 'model_providers.lmstudio.wire_api="responses"' `
    $Workspace
} else {
  & codex `
    --oss `
    --local-provider lmstudio `
    -m deepseek-v4-pro `
    -C $Workspace
}
