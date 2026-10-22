@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_setup.ps1"
if errorlevel 1 pause
