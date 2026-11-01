@echo off
REM My Hostel - run the Flutter app in Chrome.
REM OneDrive locks build files, so the app is copied to a normal folder first
REM (%LOCALAPPDATA%\MyHostel\app) and run from there. Your files in OneDrive are not changed.
REM The Supabase Project URL and public key are filled in by get-keys.ps1 and remembered in app\run-config.txt.
REM TESTING: the app opens at http://localhost:5555 and the student joining pages also work in Chrome
REM (STUDENT_WEB=true): open your hostel's join link, e.g. http://localhost:5555/j/ABC123, in a new tab.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title My Hostel - run app
set "CFG=app\run-config.txt"
set "RUNDIR=%LOCALAPPDATA%\MyHostel\app"

if not exist "%CFG%" (
  echo.
  echo First time: getting your Supabase project details ^(takes a minute^)...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-keys.ps1"
)

if exist "%CFG%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do set "%%A=%%B"
)

if "!SB_URL!"=="" (
  echo.
  echo Could not get them by itself - please paste them once.
  echo  1. Open supabase.com/dashboard, click your project, click the green "Connect" button
  echo     ^(or: Project Settings ^> API^).
  echo  2. Copy the PROJECT URL, like https://abcdefghijk.supabase.co
  set /p "SB_URL=Paste the Project URL here and press Enter: "
  echo  3. Copy the key named "anon public" or "Publishable key" ^(NOT secret / service_role^).
  set /p "SB_KEY=Paste the key here and press Enter: "
  if "!SB_URL!"=="" goto :missing
  if "!SB_KEY!"=="" goto :missing
  > "%CFG%" echo SB_URL=!SB_URL!
  >> "%CFG%" echo SB_KEY=!SB_KEY!
)

echo.
echo Copying the latest app files to %RUNDIR% ...
robocopy "%~dp0app" "%RUNDIR%" /MIR /XD build .dart_tool .idea /XF run-config.txt /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo [X] Could not copy the app files.
  goto :failed
)

echo.
echo Starting the app in Chrome... the first start takes a few minutes.
echo To stop it: press Ctrl+C in this window.
echo.
cd /d "%RUNDIR%"
call flutter pub get
if errorlevel 1 goto :failed
call flutter run -d chrome --web-port=5555 --dart-define=SUPABASE_URL=!SB_URL! --dart-define=SUPABASE_ANON_KEY=!SB_KEY! --dart-define=PUBLIC_APP_URL=http://localhost:5555 --dart-define=STUDENT_WEB=true
goto :end

:missing
echo [X] A value was empty. Run this file again.
goto :end

:failed
echo.
echo [X] Something went wrong above. Take a screenshot of this window and send it to Claude.

:end
echo.
pause
endlocal
