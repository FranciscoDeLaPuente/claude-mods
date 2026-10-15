@echo off
rem Lanzador de install.ps1. Doble clic: instala todos los mods en Windows.
rem Desde una consola acepta las mismas opciones: install.cmd -Target both, install.cmd -List...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set RC=%ERRORLEVEL%
if "%~1"=="" pause
exit /b %RC%
