<# : this line lets the same file run as a batch file and as PowerShell
@echo off
REM My Hostel - put the latest app online at your own short link (Netlify), e.g. https://myhostel-test.netlify.app
REM TEST SITE: real Supabase data, test OTP 123456, student joining works in the browser (STUDENT_WEB=true).
REM First time: asks for a Netlify access key and a site name.
REM After that: double-click to publish the newest version to the same link (2-3 minutes).
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title My Hostel - publish test site
set "CFG=app\run-config.txt"
set "PCFG=app\publish-config.txt"
set "RUNDIR=%LOCALAPPDATA%\MyHostel\app"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File"
set "MH_ROOT=%~dp0"
set "SELF=%~f0"

REM ---- Supabase details (same as run-app.bat) ----
if not exist "%CFG%" (
  echo Getting your Supabase project details ^(takes a minute^)...
  %PS% "%~dp0get-keys.ps1"
)
if exist "%CFG%" for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do set "%%A=%%B"
if "!SB_URL!"=="" (
  echo [X] Supabase details missing. Run run-app.bat once first, then this file again.
  goto :end
)

REM ---- first time: Netlify access key + site ----
set "MH_ACTION=setup"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:SELF))"
if errorlevel 1 goto :failed
for /f "usebackq tokens=1,* delims==" %%A in ("%PCFG%") do set "%%A=%%B"
set "URL=https://!SITE!.netlify.app"

REM ---- build (outside OneDrive) ----
echo.
echo Copying the latest app files...
robocopy "%~dp0app" "%RUNDIR%" /MIR /XD build .dart_tool .idea /XF run-config.txt publish-config.txt /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto :failed
cd /d "%RUNDIR%"
echo Building the web app ^(1-2 minutes^)...
call flutter pub get
if errorlevel 1 goto :failed
call flutter build web --release --dart-define=SUPABASE_URL=!SB_URL! --dart-define=SUPABASE_ANON_KEY=!SB_KEY! --dart-define=PUBLIC_APP_URL=!URL! --dart-define=STUDENT_WEB=true
if errorlevel 1 goto :failed
cd /d "%~dp0"

REM ---- publish ----
echo.
echo Publishing to !URL! ...
set "MH_ACTION=deploy"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:SELF))"
if errorlevel 1 goto :failed

echo.
echo ==============================================
echo   DONE - open on any phone or computer:
echo   !URL!
echo ==============================================
start "" "!URL!"
goto :end

:failed
echo.
echo [X] Something went wrong above. Take a screenshot of this window and send it to Claude.

:end
echo.
pause
endlocal
exit /b
#>
# ---- PowerShell part: talks to Netlify directly (no Netlify tool / Node needed) ----
#   setup   -> first time: asks for your Netlify access key and a site name, creates the site
#   deploy  -> uploads app build\web to the site (goes live at once)
# Settings are kept in app\publish-config.txt on this computer only.
$Action = $env:MH_ACTION
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $env:MH_ROOT.TrimEnd('\')
$cfgPath = Join-Path $root 'app\publish-config.txt'
$api = 'https://api.netlify.com/api/v1'

function Read-Cfg {
  $c = @{}
  if (Test-Path $cfgPath) {
    foreach ($line in Get-Content $cfgPath) { $k, $v = $line -split '=', 2; if ($k) { $c[$k.Trim()] = "$v".Trim() } }
  }
  return $c
}

$cfg = Read-Cfg

if ($Action -eq 'setup') {
  if ($cfg.TOKEN -and $cfg.SITE_ID) { exit 0 }
  Write-Host ''
  Write-Host '==== First time only ===='
  Write-Host '1. In your browser: log in to Netlify (free, "Sign up with Google" is easiest).'
  Write-Host '2. Then open:  https://app.netlify.com/user/applications#personal-access-tokens'
  Write-Host '   Click "New access token", name it  My Hostel , expiry "No expiration" (or longest), Generate.'
  Write-Host '3. Copy the token and paste it here (right-click pastes).'
  Start-Process 'https://app.netlify.com/user/applications#personal-access-tokens'
  $token = (Read-Host 'Paste the access token and press Enter').Trim()
  if (-not $token) { throw 'No token typed.' }
  $headers = @{ Authorization = "Bearer $token" }
  while ($true) {
    Write-Host ''
    Write-Host 'Choose a short name for your test link: small letters, numbers and - only.'
    Write-Host 'Example: myhostel-test  gives  https://myhostel-test.netlify.app'
    $name = (Read-Host 'Type the name and press Enter').Trim().ToLower()
    if (-not $name) { continue }
    try {
      $site = Invoke-RestMethod -Method Post -Uri "$api/sites" -Headers $headers -ContentType 'application/json' -Body (@{ name = $name } | ConvertTo-Json)
      break
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      if ($code -eq 401) { throw 'The access token was not accepted. Run this file again and paste the token again.' }
      Write-Host "That name can't be used (maybe taken). Try another one." -ForegroundColor Yellow
    }
  }
  Set-Content -Path $cfgPath -Encoding ascii -Value @("TOKEN=$token", "SITE_ID=$($site.id)", "SITE=$($site.name)")
  Write-Host "Site created: https://$($site.name).netlify.app" -ForegroundColor Green
  exit 0
}

if ($Action -eq 'deploy') {
  if (-not ($cfg.TOKEN -and $cfg.SITE_ID)) { throw 'Not set up yet. Run publish-web.bat again.' }
  $web = Join-Path $env:LOCALAPPDATA 'MyHostel\app\build\web'
  if (-not (Test-Path (Join-Path $web 'index.html'))) { throw "No web build found in $web" }
  $zip = Join-Path $env:TEMP 'myhostel-web.zip'
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Write-Host 'Packing the files...'
  # zip with forward-slash paths (Compress-Archive in Windows PowerShell can write backslashes)
  Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::Open($zip, 'Create')
  try {
    Get-ChildItem $web -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($web.Length).TrimStart('\').Replace('\', '/')
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $_.FullName, $rel, 'Optimal') | Out-Null
    }
  } finally { $z.Dispose() }
  Write-Host 'Uploading to Netlify...'
  $d = Invoke-RestMethod -Method Post -Uri "$api/sites/$($cfg.SITE_ID)/deploys" -Headers @{ Authorization = "Bearer $($cfg.TOKEN)" } -ContentType 'application/zip' -InFile $zip -TimeoutSec 600
  # wait until it is live
  for ($i = 0; $i -lt 60; $i++) {
    $s = Invoke-RestMethod -Uri "$api/deploys/$($d.id)" -Headers @{ Authorization = "Bearer $($cfg.TOKEN)" }
    if ($s.state -eq 'ready') { break }
    if ($s.state -eq 'error') { throw "Netlify could not publish: $($s.error_message)" }
    Start-Sleep -Seconds 3
  }
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  exit 0
}
