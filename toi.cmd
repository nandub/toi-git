@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toi.ps1" %*
