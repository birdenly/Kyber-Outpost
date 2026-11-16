@echo off
cd /d "%~dp0" || exit /b 1
origin_unwrapper.exe --add-dll "starwarsbattlefrontii.exe" "starwarsbattlefrontii.outpost.exe"
if not "%errorlevel%"=="0" goto end
copy /b /-y "starwarsbattlefrontii.exe" "starwarsbattlefrontii.exe.backup" || goto end
move /y "starwarsbattlefrontii.outpost.exe" "starwarsbattlefrontii.exe" || goto end
echo Setup complete.
:end
pause
