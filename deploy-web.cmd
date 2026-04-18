@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy-web.ps1" %*
set EXIT_CODE=%ERRORLEVEL%
if not "%EXIT_CODE%"=="0" (
  echo.
  echo Deploy failed with exit code %EXIT_CODE%.
  pause
  exit /b %EXIT_CODE%
)
echo.
echo Deploy finished.
pause
