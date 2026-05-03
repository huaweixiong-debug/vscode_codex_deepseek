@echo off
setlocal

:: Set proxy URL
set CODEX_OSS_BASE_URL=http://127.0.0.1:17777/v1

:: Ensure proxy is running
set START_SCRIPT=%~dp0Start-CodexDeepSeek.ps1
set LOG_DIR=%USERPROFILE%\.codex\log

:: Read key from deepseek.env in same dir
set KEY_FILE=%~dp0deepseek.env
if exist "%KEY_FILE%" (
    for /f "usebackq tokens=2 delims==" %%a in (`findstr /b "DEEPSEEK_API_KEY=" "%KEY_FILE%"`) do (
        set DEEPSEEK_API_KEY=%%a
    )
)

:: If not found, try system env
if "%DEEPSEEK_API_KEY%"=="" (
    echo [CodexDeepSeek] DEEPSEEK_API_KEY not found in %KEY_FILE%
    echo [CodexDeepSeek] Trying system environment variable...
)

:: Start proxy via PowerShell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%START_SCRIPT%" -ProxyOnly
if %ERRORLEVEL% NEQ 0 (
    echo [CodexDeepSeek] WARNING: Proxy start returned exit code %ERRORLEVEL%
)

:: Find the real codex.exe
set COEX=%USERPROFILE%\.vscode\extensions
for /d %%d in ("%COEX%\openai.chatgpt-*") do (
    if exist "%%d\bin\windows-x86_64\codex.exe" (
        set CODEX_EXE=%%d\bin\windows-x86_64\codex.exe
    )
)

:: Fallback: try WindowsApps
if "%CODEX_EXE%"=="" (
    for /d %%d in ("C:\Program Files\WindowsApps\OpenAI.Codex_*") do (
        if exist "%%d\app\resources\codex.exe" (
            set CODEX_EXE=%%d\app\resources\codex.exe
        )
    )
)

if "%CODEX_EXE%"=="" (
    echo [CodexDeepSeek] ERROR: Cannot find codex.exe
    exit /b 1
)

:: If first arg is app-server, inject DeepSeek config
if /i "%~1"=="app-server" (
    "%CODEX_EXE%" app-server -c model_provider="deepseek-codex" -c model="deepseek-v4-pro" -c model_providers.deepseek-codex.name="DeepSeek Codex" -c model_providers.deepseek-codex.base_url="http://127.0.0.1:17777/v1" -c model_providers.deepseek-codex.wire_api="responses" %2 %3 %4 %5 %6 %7 %8 %9
) else (
    "%CODEX_EXE%" %*
)
