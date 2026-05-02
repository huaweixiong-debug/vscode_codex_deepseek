$action = New-ScheduledTaskAction -Execute 'powershell' -Argument '-NoProfile -ExecutionPolicy Bypass -File "d:\Codex Deepseek\Start-CodexDeepSeek.ps1" -ProxyOnly'
$trigger = New-ScheduledTaskTrigger -AtLogon
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'CodexDeepSeekProxy' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
Write-Host "Scheduled task 'CodexDeepSeekProxy' created successfully."
