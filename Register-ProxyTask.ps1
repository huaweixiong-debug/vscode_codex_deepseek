$script = Join-Path $PSScriptRoot "Start-CodexDeepSeek.ps1"
$action = New-ScheduledTaskAction -Execute 'powershell' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -ProxyOnly"
$trigger = New-ScheduledTaskTrigger -AtLogon
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'CodexDeepSeekProxy' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
Write-Host "Scheduled task 'CodexDeepSeekProxy' created successfully."
