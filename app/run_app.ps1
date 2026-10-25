# ==========================================================
# SafeLink Mobile App Auto-Launcher
# Automatically gets live ngrok URL and runs Flutter on phone
# ==========================================================
$ErrorActionPreference = "SilentlyContinue"
$root = $PSScriptRoot
if (Test-Path "$PSScriptRoot\..\app\lib\main.dart") {
    $root = (Resolve-Path "$PSScriptRoot\..").Path
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SafeLink Mobile App Auto-Launcher                      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Fetch live ngrok URL
Write-Host "[1/3] Getting live ngrok tunnel..." -ForegroundColor Yellow
$ngrokUrl = $null
try {
    $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
    $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
} catch {}

if (-not $ngrokUrl) {
    Write-Host "      ngrok not detected on port 4040. Starting background ngrok..." -ForegroundColor DarkGray
    $npmNgrok = "$env:APPDATA\npm\node_modules\ngrok\bin\ngrok.exe"
    $ngrokArgs = "http 8000 --url=unpaved-coherent-encroach.ngrok-free.dev"
    if (Test-Path $npmNgrok) {
        Start-Process $npmNgrok -ArgumentList $ngrokArgs -WindowStyle Minimized
    } else {
        Start-Process "cmd.exe" -ArgumentList "/c ngrok $ngrokArgs" -WindowStyle Minimized
    }

    $attempts = 0
    while (-not $ngrokUrl -and $attempts -lt 8) {
        Start-Sleep -Seconds 1
        $attempts++
        try {
            $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
        } catch {}
    }
}

if ($ngrokUrl) {
    Write-Host "      Live Tunnel: $ngrokUrl" -ForegroundColor Green
} else {
    $ngrokUrl = "https://unpaved-coherent-encroach.ngrok-free.dev"
    Write-Host "      Using default: $ngrokUrl" -ForegroundColor Green
}

# 2. Read .env credentials
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

# 3. Detect connected phone
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
} catch {}

# 4. Launch Flutter
Write-Host "[3/3] Starting Flutter with live ngrok backend URL..." -ForegroundColor Green
Write-Host ""
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
