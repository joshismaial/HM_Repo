# My Hostel - talks to Netlify directly (no Netlify tool / Node needed).
#   publish-web.ps1 setup   -> first time: asks for your Netlify access key and a site name, creates the site
#   publish-web.ps1 deploy  -> uploads app build\web to the site (goes live at once)
# Settings are kept in app\publish-config.txt on this computer only.
param([string]$Action = 'deploy')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
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
