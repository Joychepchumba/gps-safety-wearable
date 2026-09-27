# SafeGuard Dev Launcher
# Run this once before pressing F5 in VS Code.
# It starts the FastAPI backend, tunnels it via ngrok,
# then auto-updates launch.json with the live URL.

param(
    [switch]$NoBackend  # Pass -NoBackend to skip starting uvicorn (if already running)
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$launchJson = "$root\.vscode\launch.json"
$backendDir = "$root\backend"
$port = 8000

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SafeGuard Dev Launcher" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check ngrok is installed ──────────────────────────────────────────────
if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] ngrok is not installed." -ForegroundColor Red
    Write-Host "  Install it from: https://ngrok.com/download" -ForegroundColor Yellow
    Write-Host "  Or via winget:   winget install ngrok.ngrok" -ForegroundColor Yellow
    exit 1
}

# ── 2. Start FastAPI backend in background ────────────────────────────────────
if (-not $NoBackend) {
    Write-Host "[1/3] Starting FastAPI backend on port $port..." -ForegroundColor Green

    # Activate venv if it exists
    $venvActivate = "$backendDir\.venv\Scripts\Activate.ps1"
    if (Test-Path $venvActivate) {
        Write-Host "      (using .venv)" -ForegroundColor DarkGray
        & $venvActivate
    }

    # Start uvicorn as a background job
    $uvicorn = Start-Job -ScriptBlock {
        param($dir, $port)
        Set-Location $dir
        if (Test-Path ".venv\Scripts\Activate.ps1") { & ".venv\Scripts\Activate.ps1" }
        uvicorn app.main:app --host 0.0.0.0 --port $port --reload 2>&1
    } -ArgumentList $backendDir, $port

    Start-Sleep -Seconds 3  # give uvicorn time to bind

    # Quick health check
    try {
        $health = Invoke-RestMethod "http://localhost:$port/" -TimeoutSec 5
        Write-Host "      Backend healthy: $($health.status)" -ForegroundColor DarkGreen
    } catch {
        Write-Host "      Backend may still be starting — continuing..." -ForegroundColor Yellow
    }
} else {
    Write-Host "[1/3] Skipping backend start (-NoBackend flag set)" -ForegroundColor Yellow
}

# ── 3. Start ngrok tunnel ─────────────────────────────────────────────────────
Write-Host "[2/3] Starting ngrok tunnel..." -ForegroundColor Green

# Kill any existing ngrok on this port
Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# Start ngrok in background
$npmNgrok = "$env:APPDATA\npm\node_modules\ngrok\bin\ngrok.exe"
if (Test-Path $npmNgrok) {
    Start-Process $npmNgrok -ArgumentList "http $port" -WindowStyle Minimized
} else {
    Start-Process "cmd.exe" -ArgumentList "/c ngrok http $port" -WindowStyle Minimized
}

# Wait for ngrok to be ready and expose its local API
$ngrokUrl = $null
$attempts = 0
Write-Host "      Waiting for ngrok tunnel..." -ForegroundColor DarkGray

while (-not $ngrokUrl -and $attempts -lt 15) {
    Start-Sleep -Seconds 1
    $attempts++
    try {
        $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
        $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
    } catch {
        # ngrok not ready yet
    }
}

if (-not $ngrokUrl) {
    Write-Host "[ERROR] Could not get ngrok URL after $attempts attempts." -ForegroundColor Red
    Write-Host "  Make sure ngrok started correctly. Try opening http://127.0.0.1:4040 in a browser." -ForegroundColor Yellow
    exit 1
}

Write-Host "      Tunnel live: $ngrokUrl" -ForegroundColor DarkGreen

# ── 4. Patch launch.json with the fresh backend URL ──────────────────────────
Write-Host "[3/3] Updating launch.json with backend URL..." -ForegroundColor Green

$json = Get-Content $launchJson -Raw | ConvertFrom-Json

foreach ($config in $json.configurations) {
    $args = [System.Collections.Generic.List[string]]$config.args

    # Remove any existing BACKEND_URL dart-define
    $existing = $args | Where-Object { $_ -like "--dart-define=BACKEND_URL=*" }
    foreach ($e in $existing) { $args.Remove($e) | Out-Null }

    # Add the fresh one
    $args.Add("--dart-define=BACKEND_URL=$ngrokUrl")
    $config.args = $args.ToArray()
}

$json | ConvertTo-Json -Depth 10 | Set-Content $launchJson -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  All done! Now press F5 in VS Code." -ForegroundColor Green
Write-Host "  Backend:  http://localhost:$port" -ForegroundColor White
Write-Host "  Tunnel:   $ngrokUrl" -ForegroundColor White
Write-Host "  ngrok UI: http://127.0.0.1:4040" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C here to stop the backend when done." -ForegroundColor DarkGray

# Keep script alive so backend job stays running
if (-not $NoBackend) {
    try {
        while ($true) {
            $out = Receive-Job $uvicorn
            if ($out) { Write-Host $out -ForegroundColor DarkGray }
            Start-Sleep -Seconds 2
        }
    } finally {
        Write-Host "`nStopping backend..." -ForegroundColor Yellow
        Stop-Job $uvicorn
        Remove-Job $uvicorn
        Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}
