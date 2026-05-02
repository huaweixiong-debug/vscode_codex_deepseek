@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-CodexDeepSeek.ps1" -Workspace "%USERPROFILE%" -App
