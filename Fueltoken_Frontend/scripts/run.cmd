@echo off
REM FuelToken — Windows (CMD). Depuis la racine :  scripts\run.cmd
REM Ou double-clic sur ce fichier (lance Flutter depuis la racine du depot).

setlocal
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
exit /b %ERRORLEVEL%
