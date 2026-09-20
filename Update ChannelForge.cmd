@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge is incomplete. The bundled PowerShell runtime is missing.
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%tools\Invoke-ChannelForgeAutoUpdate.ps1" -PackageRoot "%ROOT%" -InstallRoot "%LOCALAPPDATA%\ChannelForge" -Apply %*
if errorlevel 1 (
  echo.
  echo ChannelForge update failed. The previous application files should have been restored.
  pause
  exit /b 1
)
echo ChannelForge update completed.
pause
endlocal
