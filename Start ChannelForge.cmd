@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge is incomplete. The bundled PowerShell runtime is missing.
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Start-ChannelForge.ps1" %*
if errorlevel 1 (
  echo.
  echo ChannelForge could not start. Review state\runtime\server.stderr.log for details.
  pause
  exit /b 1
)
endlocal
