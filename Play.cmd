@echo off
rem DF3D: double-click to boot Dwarf Fortress (hidden) with the bridge and
rem choose a saved fort in Godot. Close Godot to end the session; closing
rem this window also ends it (DF is closed automatically when this window closes).
rem
rem Needs: the repo built (build\ and the Godot extension), DFHack + the
rem df3d plugin installed into the Steam DF folder. See README.md.
setlocal
cd /d "%~dp0"
title DF3D play
rem Pass -Attach to connect to running DF; PowerShell validates ownership.
rem Optional diagnostics: -Profile basic or -Profile deep (default: off).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\smoke\play_live.ps1" %*
if errorlevel 1 (
  echo.
  echo The session ended with an error. See the diagnostic above.
  pause
)
endlocal
