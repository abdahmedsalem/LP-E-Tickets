@echo off
REM LP E-Tickets - Web LAN launcher. Depuis la racine : scripts\run_web.cmd

setlocal
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_web.ps1"
exit /b %ERRORLEVEL%
