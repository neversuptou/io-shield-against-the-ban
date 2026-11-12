@echo off
setlocal
rem Register + enable + start the AI bridge killswitch watchdog (RUN ELEVATED).
rem The task references this script's directory, so the client folder is portable.
set "SCRIPT=%~dp0tunnel-watchdog.ps1"
schtasks /Create /TN "AI-Bridge-Watchdog" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%SCRIPT%\"" /SC ONLOGON /RL HIGHEST /F
schtasks /Change /TN "AI-Bridge-Watchdog" /ENABLE
schtasks /Run /TN "AI-Bridge-Watchdog"
schtasks /Query /TN "AI-Bridge-Watchdog"
echo.
echo Done. Killswitch now follows the Hermes lifecycle.
pause
