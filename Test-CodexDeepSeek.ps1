param(
  [string]$Prompt = "reply exactly local-deepseek-ok",
  [string]$Workspace = "D:\Claude"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartScript = Join-Path $Root "Start-CodexDeepSeek.ps1"

& $StartScript -Workspace $Workspace -ProxyOnly | Out-Null

$env:CODEX_OSS_BASE_URL = "http://127.0.0.1:17777/v1"
& codex exec `
  --oss `
  --local-provider lmstudio `
  -m deepseek-v4-pro `
  --dangerously-bypass-approvals-and-sandbox `
  --skip-git-repo-check `
  -C $Workspace `
  $Prompt
