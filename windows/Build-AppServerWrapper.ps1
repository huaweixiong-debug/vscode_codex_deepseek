param(
  [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "CodexDeepSeekAppServer.exe")
)

$ErrorActionPreference = "Stop"

$candidates = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
  "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$csc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
  throw "csc.exe not found. Install .NET Framework build tools or compile CodexDeepSeekAppServer.cs manually."
}

& $csc /nologo /target:exe /out:$OutputPath (Join-Path $PSScriptRoot "CodexDeepSeekAppServer.cs")
Write-Host "Built $OutputPath"
