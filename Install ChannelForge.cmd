@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge cannot run because some of its files are missing.
  echo Download ChannelForge again, unzip it completely, then try again.
  echo Details: The bundled PowerShell runtime is missing: runtime\pwsh\pwsh.exe
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Install-ChannelForgeWindowsBundle.ps1" -PackageRoot "%ROOT:~0,-1%" %*
if errorlevel 1 (
  echo.
  echo ChannelForge could not be installed. The reason is shown above this message.
  echo Fix that, then double-click Install ChannelForge.cmd again.
  pause
  exit /b 1
)
echo ChannelForge is installed. Use Start ChannelForge.cmd from the installed folder.
pause
endlocal
