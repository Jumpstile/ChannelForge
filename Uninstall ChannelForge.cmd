@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge is incomplete. The bundled PowerShell runtime is missing.
  pause
  exit /b 1
)
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Uninstall-ChannelForgeWindowsBundle.ps1" -InstallRoot "%LOCALAPPDATA%\ChannelForge" %*
set "UNINSTALL_EXIT=%errorlevel%"
for /l %%N in (1,1,60) do (
  if not exist "%LOCALAPPDATA%\ChannelForge\package-manifest.json" goto :uninstall_done
  timeout /t 1 /nobreak >nul
)
:uninstall_done
if not "%UNINSTALL_EXIT%"=="0" (
  echo.
  echo ChannelForge uninstall failed.
  pause
  exit /b 1
)
echo ChannelForge application files removed. User data was retained.
pause
endlocal
