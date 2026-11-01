@echo off
REM My Hostel - switch on the server functions in your Supabase project (student OTP, student details,
REM uploads, owner actions). TEST MODE: no SMS is sent and every OTP is 123456.
REM Run setup-database.bat first (it links this folder to your project). Safe to run again after changes.
setlocal
cd /d "%~dp0"
title My Hostel - server functions
if not exist "supabase\.temp\linked-project.json" (
  echo [X] This folder is not linked to Supabase yet. Run setup-database.bat first.
  goto :end
)
set "SB=call npx --yes supabase@latest"

echo.
echo Step 1 of 2: test settings ^(OTP is always 123456, no SMS^)...
%SB% secrets set SMS_DEV_MODE=true
if errorlevel 1 goto :failed

echo.
echo Step 2 of 2: uploading the functions ^(a few minutes^)...
for %%F in (student-otp student-api sms-hook) do (
  echo  - %%F
  %SB% functions deploy %%F --no-verify-jwt --use-api
  if errorlevel 1 goto :failed
)
for %%F in (owner-actions purge-files rent-reminders) do (
  echo  - %%F
  %SB% functions deploy %%F --use-api
  if errorlevel 1 goto :failed
)

echo.
echo ==============================================
echo   DONE - server functions are on ^(test mode^).
echo ==============================================
goto :end

:failed
echo.
echo [X] Something went wrong above. Take a screenshot of this window and send it to Claude.

:end
echo.
pause
endlocal
