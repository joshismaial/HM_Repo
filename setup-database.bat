@echo off
REM My Hostel - put the database online in your Supabase project.
REM Double-click this file. Safe to run again later: it only adds database changes that are not there yet.
setlocal
cd /d "%~dp0"
title My Hostel - database setup
echo.
echo ==============================================
echo   My Hostel - database setup (Supabase)
echo ==============================================
echo.

REM 1. Node.js is needed to run the Supabase tool (you already use it for Expo).
where npx >nul 2>nul
if errorlevel 1 (
  echo [X] Node.js is not installed. Install it from https://nodejs.org ^(LTS^), then run this file again.
  goto :end
)
set "SB=call npx --yes supabase@latest"

echo Step 1 of 4: getting the Supabase tool ^(first time takes a minute^)...
%SB% --version
if errorlevel 1 (
  echo [X] Could not start the Supabase tool. Check your internet and run this file again.
  goto :end
)

REM 2. Make supabase\config.toml once (your migrations are not changed).
if not exist "supabase\config.toml" (
  echo.
  echo Step 2 of 4: preparing the folder. If it asks questions, just press Enter.
  %SB% init
  if errorlevel 1 goto :failed
) else (
  echo Step 2 of 4: folder already prepared.
)

REM 3. Log in (opens your browser once).
echo.
echo Step 3 of 4: log in to Supabase. Your browser will open - log in and come back here.
%SB% login
if errorlevel 1 goto :failed

REM 4. Link to your project and push.
echo.
echo Step 4 of 4: connect to your project.
echo Your PROJECT ID is in Supabase: Project Settings ^> General ^> Project ID
echo ^(also the part before .supabase.co in your project URL, e.g. abcdxyzabcdxyz^)
set /p "REF=Paste your Project ID and press Enter: "
if "%REF%"=="" (
  echo [X] No Project ID typed.
  goto :end
)
echo.
echo It will now ask for your DATABASE PASSWORD ^(the one you set when creating the project^).
echo Note: the password does not show while you type - that is normal.
%SB% link --project-ref %REF%
if errorlevel 1 goto :failed

echo.
echo Uploading the database changes. If it asks "Do you want to push", type Y and press Enter.
%SB% db push
if errorlevel 1 goto :failed

echo.
echo ==============================================
echo   DONE - your database is online.
echo ==============================================
echo One more step, once only: Supabase ^> SQL editor, run
echo   insert into private.settings (name, value) values ('id_encryption_key', 'YOUR-LONG-RANDOM-SECRET');
echo Keep a copy of that secret safe - without it, saved ID numbers can't be read.
goto :end

:failed
echo.
echo [X] Something went wrong above. Take a screenshot of this window and send it to Claude.

:end
echo.
pause
endlocal
