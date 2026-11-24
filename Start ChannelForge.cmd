@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge cannot run because some of its files are missing.
  echo Run Install ChannelForge.cmd again to fix this.
  echo Details: The bundled PowerShell runtime is missing: runtime\pwsh\pwsh.exe
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Start-ChannelForge.ps1" %*
if errorlevel 1 (
  echo.
  echo ChannelForge could not start. The reason is shown above this message.
  echo More details are in state\runtime\server.stderr.log
  pause
  exit /b 1
)
endlocal
