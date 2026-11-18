@echo off
setlocal
set "ROOT=%~dp0"
set "PW=%ROOT%runtime\pwsh\pwsh.exe"
if not exist "%PW%" (
  echo ChannelForge is incomplete. The bundled PowerShell runtime is missing.
  pause
  exit /b 1
)
set "UNINSTALL_ARGS=%*"
set "PURGED="
if not "%~1"=="" goto :run_uninstall
echo What do you want to do?
echo.
echo   1. Keep my lineup and saved sources
echo      Removes only the application files. Your data stays for a later reinstall.
echo.
echo   2. Delete all ChannelForge data
echo      Removes the application AND your lineup, saved sources, and settings.
echo      This cannot be undone.
echo.
set "CHOICE="
set /p "CHOICE=Type 1 or 2 and press Enter (anything else cancels): "
if "%CHOICE%"=="1" goto :run_uninstall
if not "%CHOICE%"=="2" goto :cancelled
set "CONFIRM="
set /p "CONFIRM=To delete everything, type DELETE in capital letters and press Enter: "
if not "%CONFIRM%"=="DELETE" goto :cancelled
set "UNINSTALL_ARGS=-PurgeData -ConfirmPurge"
set "PURGED=1"
:run_uninstall
"%PW%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%scripts\Uninstall-ChannelForgeWindowsBundle.ps1" -InstallRoot "%LOCALAPPDATA%\ChannelForge" %UNINSTALL_ARGS%
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
if defined PURGED (
  echo ChannelForge application and user data removed.
) else (
  echo ChannelForge application files removed. User data was retained.
)
pause
exit /b 0
:cancelled
echo.
echo Cancelled. Nothing was removed.
pause
endlocal
