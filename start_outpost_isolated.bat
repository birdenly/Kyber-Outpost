@echo off
setlocal
cd /d "%~dp0" || exit /b 1
if not exist "kyber_launcher.exe" (
    echo Place this BAT beside kyber_launcher.exe.
    pause
    exit /b 1
)
set "OUTPOST_PROFILE=%TEMP%\KyberOutpost-%RANDOM%-%RANDOM%"
set "APPDATA=%OUTPOST_PROFILE%\Roaming"
set "LOCALAPPDATA=%OUTPOST_PROFILE%\Local"
set "TEMP=%OUTPOST_PROFILE%\Temp"
set "TMP=%TEMP%"
mkdir "%APPDATA%" "%LOCALAPPDATA%" "%TEMP%" || exit /b 1
start "" "%~dp0kyber_launcher.exe"
