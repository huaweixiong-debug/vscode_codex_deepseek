@echo off
REM Start the DeepSeek Codex proxy (keeps running in background)
powershell -NoProfile -ExecutionPolicy Bypass -File "d:\Codex Deepseek\Start-CodexDeepSeek.ps1" -ProxyOnly
echo Proxy started. You can now use Codex with DeepSeek.
pause
