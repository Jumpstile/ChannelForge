@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge is incomplete. The bundled PowerShell runtime is missing.
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Install-ChannelForgeWindowsBundle.ps1" -PackageRoot "%ROOT%" %*
if errorlevel 1 (
  echo.
  echo ChannelForge installation failed.
  pause
  exit /b 1
)
echo ChannelForge is installed. Use Start ChannelForge.cmd from the installed folder.
pause
endlocal
