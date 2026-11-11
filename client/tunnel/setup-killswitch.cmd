@echo off
rem Register + enable + start the AI bridge killswitch watchdog (RUN ELEVATED).
rem Ties the direct-443 block to the Hermes lifecycle:
rem   Hermes running -> block ON  (no tool can reach AI providers directly)
rem   Hermes closed  -> block OFF (direct provider use works again)
schtasks /Create /TN "AI-Bridge-Watchdog" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\Programms\IO\hermes\hermes-agent\ai-bridge\tunnel-watchdog.ps1" /SC ONLOGON /RL HIGHEST /F
schtasks /Change /TN "AI-Bridge-Watchdog" /ENABLE
schtasks /Run /TN "AI-Bridge-Watchdog"
schtasks /Query /TN "AI-Bridge-Watchdog"
echo.
echo Done. Killswitch now follows the Hermes lifecycle.
pause
