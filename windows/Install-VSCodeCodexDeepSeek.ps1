param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "CodexDeepSeek"),
  [string]$DeepSeekApiKey = "",
  [switch]$SkipProxyStart
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[Codex DeepSeek] $Message"
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

function Get-JsonObject {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw.Trim().Length -gt 0) {
      return $raw | ConvertFrom-Json
    }
  }
  return [pscustomobject]@{}
}

function Set-JsonProperty {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Value
  )
  $prop = $Object.PSObject.Properties[$Name]
  if ($prop) {
    $prop.Value = $Value
  } else {
    Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Protect-SecretFile {
  param([string]$Path)
  try {
    & icacls $Path /inheritance:r | Out-Null
    & icacls $Path /grant:r "$env:USERNAME:F" | Out-Null
  } catch {
    Write-Warning "Unable to tighten ACL for ${Path}: $($_.Exception.Message)"
  }
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ProxySource = Join-Path $RepoRoot "deepseek-codex-proxy.js"
$StarterSource = Join-Path $RepoRoot "Start-CodexDeepSeek.ps1"
$WrapperSource = Join-Path $PSScriptRoot "CodexDeepSeekAppServer.cs"
$BuilderSource = Join-Path $PSScriptRoot "Build-AppServerWrapper.ps1"

foreach ($required in @($ProxySource, $StarterSource, $WrapperSource, $BuilderSource)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Missing required file: $required"
  }
}

Write-Step "Installing files to $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -LiteralPath $ProxySource -Destination (Join-Path $InstallDir "deepseek-codex-proxy.js") -Force
Copy-Item -LiteralPath $StarterSource -Destination (Join-Path $InstallDir "Start-CodexDeepSeek.ps1") -Force
Copy-Item -LiteralPath $WrapperSource -Destination (Join-Path $InstallDir "CodexDeepSeekAppServer.cs") -Force
Copy-Item -LiteralPath $BuilderSource -Destination (Join-Path $InstallDir "Build-AppServerWrapper.ps1") -Force

$CodexHome = Join-Path $env:USERPROFILE ".codex"
$SecretFile = Join-Path $CodexHome "deepseek.env"
$InstallSecretFile = Join-Path $InstallDir "deepseek.env"
New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null

if (-not $DeepSeekApiKey) {
  if ($env:DEEPSEEK_API_KEY) {
    $DeepSeekApiKey = $env:DEEPSEEK_API_KEY
  } elseif (Test-Path -LiteralPath $SecretFile) {
    $existing = Get-Content -LiteralPath $SecretFile -ErrorAction SilentlyContinue |
      Where-Object { $_ -match '^\s*DEEPSEEK_API_KEY\s*=' } |
      Select-Object -First 1
    if ($existing) {
      $DeepSeekApiKey = ($existing -replace '^\s*DEEPSEEK_API_KEY\s*=\s*', '').Trim().Trim('"').Trim("'")
    }
  }
}

if (-not $DeepSeekApiKey) {
  $DeepSeekApiKey = Read-SecretLine "Enter DEEPSEEK_API_KEY"
}

if (-not $DeepSeekApiKey) {
  throw "DEEPSEEK_API_KEY is required."
}

$SecretValue = "DEEPSEEK_API_KEY=$DeepSeekApiKey"
try {
  Write-Step "Writing DeepSeek key to $SecretFile"
  Set-Content -LiteralPath $SecretFile -Value $SecretValue -Encoding ASCII
  Protect-SecretFile -Path $SecretFile
} catch {
  Write-Warning "Unable to write ${SecretFile}: $($_.Exception.Message)"
  Write-Step "Writing DeepSeek key to fallback file $InstallSecretFile"
  Set-Content -LiteralPath $InstallSecretFile -Value $SecretValue -Encoding ASCII
  Protect-SecretFile -Path $InstallSecretFile
}

$WrapperExe = Join-Path $InstallDir "CodexDeepSeekAppServer.exe"
Write-Step "Building VSCode app-server wrapper"
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir "Build-AppServerWrapper.ps1") -OutputPath $WrapperExe

$SettingsDir = Join-Path $env:APPDATA "Code\User"
$SettingsPath = Join-Path $SettingsDir "settings.json"
New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null

Write-Step "Updating VSCode settings.json"
$settings = Get-JsonObject -Path $SettingsPath
Set-JsonProperty -Object $settings -Name "chatgpt.runCodexInWindowsSubsystemForLinux" -Value $false
Set-JsonProperty -Object $settings -Name "chatgpt.cliExecutable" -Value $WrapperExe
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8

if (-not $SkipProxyStart) {
  Write-Step "Starting DeepSeek proxy"
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir "Start-CodexDeepSeek.ps1") -ProxyOnly
}

Write-Step "Done"
Write-Host ""
Write-Host "VSCode Codex is now configured to launch:"
Write-Host "  $WrapperExe"
Write-Host ""
Write-Host "Next step: reload VSCode with 'Developer: Reload Window', then test Codex."
Write-Host "Verify real routing with:"
Write-Host "  Get-Content `"$env:USERPROFILE\.codex\log\deepseek-codex-proxy.log`" -Tail 20"
