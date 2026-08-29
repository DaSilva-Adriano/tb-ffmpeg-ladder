@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0ffmpeg.exe" (
  echo ffmpeg.exe was not found next to this script.
  echo Expected:
  echo   %~dp0ffmpeg.exe
  echo Full build: https://www.gyan.dev/ffmpeg/builds/
  pause
  exit /b 1
)

if not exist "%~dp0convert_4k_ladder.ps1" (
  echo convert_4k_ladder.ps1 is missing next to this .bat
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0convert_4k_ladder.ps1" -ScriptDir "%~dp0." -InputDir "%~dp0input" -OutputDir "%~dp0output"
echo.
pause
