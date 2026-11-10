@echo off
rem Hermes desktop/CLI launcher. Pins HERMES_HOME to the project home and routes
rem all non-loopback HTTP(S) through the bridge SOCKS (127.0.0.1:18081).
rem
rem Set IO_HOME to the directory that contains hermes-agent/ and profiles/,
rem and PY to your Python (Hermes bundles one under tools/python-*/python.exe).

set "IO_HOME=CHANGE-ME"
set "PY=python"

"%PY%" -I "%~dp0launch.py" --profile io desktop
