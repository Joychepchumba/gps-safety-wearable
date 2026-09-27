# One-click script to run Flutter on phone with the fresh ngrok URL automatically
$root = Split-Path -Parent $PSScriptRoot
$syncScript = "$PSScriptRoot\sync_ngrok.ps1"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   SafeLink Mobile App Auto-Launcher         " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# 1. Sync & fetch live ngrok URL
Write-Host "[1/3] Getting live ngrok tunnel..." -ForegroundColor Yellow
$ngrokUrl = (& powershell -ExecutionPolicy Bypass -File $syncScript | Select-Object -Last 1).Trim()
Write-Host "      Live Tunnel: $ngrokUrl" -ForegroundColor Green

# 2. Read .env for Supabase credentials
$envFile = "$root\.env"
$supabaseUrl = "https://afagwdhpjnnbueiyjmde.supabase.co"
$supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmYWd3ZGhwam5uYnVlaXlqbWRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTkzMzUsImV4cCI6MjEwNTQ5NTMzNX0.Qw_rs_KJOZF8RkXWW62QBKnSafzJFkt9YBPqCRo9mlA"

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $k = $parts[0].Trim()
            $v = $parts[1].Trim().Trim("'").Trim('"')
            if ($k -eq "SUPABASE_URL") { $supabaseUrl = $v }
            if ($k -eq "SUPABASE_ANON_KEY") { $supabaseAnonKey = $v }
        }
    }
}

# 3. Detect connected Android phone
Write-Host "[2/3] Detecting connected phone..." -ForegroundColor Yellow
$phoneId = $null
try {
    $devicesJson = flutter devices --machine | ConvertFrom-Json
    $phone = $devicesJson | Where-Object { $_.targetPlatform -like "*android*" -and -not $_.emulator } | Select-Object -First 1
    if (-not $phone) {
        $phone = $devicesJson | Where-Object { $_.targetPlatform -like "*android*" } | Select-Object -First 1
    }
    if ($phone) {
        $phoneId = $phone.id
        Write-Host "      Target Device: $($phone.name) ($($phone.id))" -ForegroundColor Green
    }
} catch {
    Write-Host "      Could not parse devices list automatically." -ForegroundColor DarkGray
}

Write-Host "[3/3] Starting Flutter..." -ForegroundColor Green
Set-Location "$root\app"

$cmdArgs = @(
    "run",
    "--dart-define=SUPABASE_URL=$supabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey",
    "--dart-define=BACKEND_URL=$ngrokUrl"
)

if ($phoneId) {
    $cmdArgs = @("-d", $phoneId) + $cmdArgs
}

& flutter @cmdArgs
