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
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%tools\Invoke-ChannelForgeAutoUpdate.ps1" -PackageRoot "%ROOT:~0,-1%" -InstallRoot "%LOCALAPPDATA%\ChannelForge" -Apply %*
if errorlevel 1 (
  echo.
  echo ChannelForge could not be updated. Your previous version should have been put back.
  echo The reason is shown above this message. Fix that, then try again.
  pause
  exit /b 1
)
echo ChannelForge update completed.
pause
endlocal
