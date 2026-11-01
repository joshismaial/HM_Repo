@echo off
rem Use this if your phone cannot connect over Wi-Fi.
cd /d "%~dp0"
call npx expo start --tunnel
pause
