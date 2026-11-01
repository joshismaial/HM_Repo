<# :
@echo off
REM My Hostel - save your Cloudflare R2 keys in Supabase (private server settings).
REM The keys stay on your computer and in Supabase only. Do not send them to anyone.
title My Hostel - Cloudflare R2 keys
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [char]10)"
echo.
pause
exit /b
#>
$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'supabase\.temp\linked-project.json')) {
  Write-Host '[X] This folder is not linked to Supabase yet. Run setup-database.bat first.' -ForegroundColor Red
  return
}
Write-Host ''
Write-Host 'Paste each value from Cloudflare and press Enter.' -ForegroundColor Cyan
Write-Host '(Right-click in this window pastes.)'
Write-Host ''
$acct = (Read-Host '1. Account ID').Trim()
$key  = (Read-Host '2. Access Key ID').Trim()
$sec  = Read-Host '3. Secret Access Key (hidden while you paste)' -AsSecureString
$secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)).Trim()
$bucket = (Read-Host '4. Bucket name [press Enter for myhostel-files]').Trim()
if (-not $bucket) { $bucket = 'myhostel-files' }
if (-not $acct -or -not $key -or -not $secret) {
  Write-Host '[X] One of the values is empty. Run this file again.' -ForegroundColor Red
  return
}
if ($acct.Length -ne 32) { Write-Host '[!] Account ID is usually 32 letters/numbers - please double-check it.' -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Saving in Supabase...'
& npx --yes supabase@latest secrets set "R2_ACCOUNT_ID=$acct" "R2_ACCESS_KEY_ID=$key" "R2_SECRET_ACCESS_KEY=$secret" "R2_BUCKET=$bucket"
if ($LASTEXITCODE -ne 0) {
  Write-Host '[X] Could not save. Take a screenshot of this window and send it to Claude (the secret is not shown).' -ForegroundColor Red
  return
}
Write-Host ''
Write-Host '=============================================='
Write-Host '  DONE - R2 keys are saved in Supabase.'
Write-Host '  Photos still use Supabase until Claude switches the code.'
Write-Host '=============================================='
