# My Hostel - gets your Supabase Project URL and public (anon) key for run-app.bat.
# Uses the project this folder is linked to (setup-database.bat did that) and your Supabase login.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ref = (Get-Content (Join-Path $root 'supabase\.temp\linked-project.json') -Raw | ConvertFrom-Json).ref
if (-not $ref) { throw 'This folder is not linked to a Supabase project yet. Run setup-database.bat first.' }
Write-Host "Getting the app key for project $ref ..."
$json = (& npx --yes supabase@latest projects api-keys --project-ref $ref -o json 2>$null) | Out-String
$keys = $json | ConvertFrom-Json
$k = $keys | Where-Object { $_.name -eq 'anon' } | Select-Object -First 1
if (-not $k) { $k = $keys | Where-Object { $_.type -eq 'publishable' } | Select-Object -First 1 }
if (-not $k -or -not $k.api_key) { throw 'Could not read the public key.' }
Set-Content -Path (Join-Path $root 'app\run-config.txt') -Encoding ascii -Value @("SB_URL=https://$ref.supabase.co", "SB_KEY=$($k.api_key)")
Write-Host "Got it: https://$ref.supabase.co"
