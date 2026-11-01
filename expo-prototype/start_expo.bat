@echo off
rem My Hostel - Expo prototype. Double-click to set up and start.
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is not installed.
  echo Install the LTS version from https://nodejs.org then run this file again.
  pause
  exit /b 1
)
if not exist node_modules (
  echo First time setup - installing Expo. This takes a few minutes...
  (
    echo ===== node --version
    call node --version
    echo ===== npm install
    call npm install
    echo ===== expo install
    call npx expo install react react-native react-native-safe-area-context @expo/vector-icons expo-status-bar expo-font @expo-google-fonts/plus-jakarta-sans
    echo ===== DONE
  ) > setup_result.txt 2>&1
  type setup_result.txt
)
echo.
echo Starting... Scan the QR code below with the Expo Go app on your phone.
echo Your phone and this computer must be on the same Wi-Fi.
echo If the phone cannot connect, close this window and run start_tunnel.bat instead.
echo.
call npx expo start
pause
