@echo off
REM My Hostel - build a TEST APK to install on an Android phone (no Play Store needed).
REM Uses the same Supabase test project as run-app.bat (app\run-config.txt).
REM The APK is saved as  HM\apk\MyHostel-test.apk  - send it to your phone (WhatsApp / Drive / USB)
REM and tap it to install (allow "Install unknown apps" once).
REM Note: this is a test APK signed with the debug key. The Play Store version is built differently later.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title My Hostel - build test APK
set "CFG=app\run-config.txt"

echo.
echo ==============================================
echo   My Hostel - build test APK for Android
echo ==============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [X] Flutter was not found. Open a new window after installing Flutter, then run this file again.
  goto :end
)

REM ---- Supabase test project details (filled in by run-app.bat / get-keys.ps1)
if not exist "%CFG%" (
  echo First time: getting your Supabase project details ^(takes a minute^)...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-keys.ps1"
)
if exist "%CFG%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do set "%%A=%%B"
)
if "!SB_URL!"=="" (
  echo [X] Supabase details are missing. Run run-app.bat once first, then run this file again.
  goto :end
)
if "!SB_KEY!"=="" (
  echo [X] Supabase key is missing. Run run-app.bat once first, then run this file again.
  goto :end
)

REM ---- Android SDK check
set "SDK_OK="
if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools" set "SDK_OK=1"
if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%\platform-tools" set "SDK_OK=1"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools" set "SDK_OK=1"
if not defined SDK_OK (
  echo [X] The Android SDK is not installed on this PC yet. It is needed to make an APK.
  echo.
  echo     1. Download and install Android Studio:  https://developer.android.com/studio
  echo     2. Open Android Studio once and let it finish "Setup Wizard" ^(Standard^).
  echo        It downloads the Android SDK ^(about 1-2 GB^).
  echo     3. Open a new Command Prompt and run:  flutter doctor --android-licenses
  echo        Press  y  and Enter for each question.
  echo     4. Run this file again.
  goto :end
)

REM Some internet providers make Java downloads time out over IPv6 - use IPv4 for Gradle.
set "GRADLE_OPTS=-Djava.net.preferIPv4Stack=true -Dorg.gradle.internal.http.connectionTimeout=120000 -Dorg.gradle.internal.http.socketTimeout=120000"
echo Step 1 of 3: getting packages...
cd /d "%~dp0app"
call flutter pub get
if errorlevel 1 goto :failed

echo.
echo Step 2 of 3: building the APK ^(the first time takes 5-15 minutes^)...
call flutter build apk --release --dart-define=SUPABASE_URL=!SB_URL! --dart-define=SUPABASE_ANON_KEY=!SB_KEY!
if errorlevel 1 goto :failed

echo.
echo Step 3 of 3: copying the APK...
cd /d "%~dp0"
if not exist "apk" mkdir "apk"
copy /y "app\build\app\outputs\flutter-apk\app-release.apk" "apk\MyHostel-test.apk" >nul
if errorlevel 1 goto :failed

echo.
echo ==============================================
echo   Done!  Your test APK is here:
echo   %~dp0apk\MyHostel-test.apk
echo ==============================================
echo.
echo   Send it to your phone ^(WhatsApp to yourself, Google Drive, or USB cable^),
echo   tap it, allow "Install unknown apps" if asked, then Install.
echo   OTP codes in test mode are always 123456.
explorer "%~dp0apk"
goto :end

:failed
echo.
echo [X] Something went wrong above. Take a screenshot of this window and send it to Claude.

:end
echo.
pause
endlocal
