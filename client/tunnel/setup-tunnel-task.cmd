@echo off
rem Register + start the hidden AI bridge tunnel keep-alive (elevated, once).
rem Usage: setup-tunnel-task.cmd [path\to\tunnel.ps1]   (defaults to tunnel.ps1 next to this file)
set "TUNNEL=%~f1"
if "%TUNNEL%"=="" set "TUNNEL=%~dp0tunnel.ps1"

schtasks /Create /TN "AI-Bridge-Tunnel" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%TUNNEL%\"" /SC ONLOGON /RL HIGHEST /F
schtasks /Run /TN "AI-Bridge-Tunnel"
schtasks /Query /TN "AI-Bridge-Tunnel"
pause
