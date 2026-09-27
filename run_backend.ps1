# ==========================================================
# SafeLink Backend Auto-Runner
# Automatically launches ngrok, syncs URLs, and starts uvicorn
# ==========================================================
$ErrorActionPreference = "SilentlyContinue"
$root = $PSScriptRoot
if (Test-Path "$PSScriptRoot\..\backend\app\main.py") {
    $root = (Resolve-Path "$PSScriptRoot\..").Path
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SafeLink Backend Server + ngrok Tunnel                 " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Start or detect ngrok
Write-Host "[1/3] Checking ngrok tunnel..." -ForegroundColor Yellow
$ngrokUrl = $null
try {
    $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
    $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
} catch {}

if (-not $ngrokUrl) {
    Write-Host "      Starting background ngrok tunnel on port 8000..." -ForegroundColor DarkGray
    $npmNgrok = "$env:APPDATA\npm\node_modules\ngrok\bin\ngrok.exe"
    if (Test-Path $npmNgrok) {
        Start-Process $npmNgrok -ArgumentList "http 8000" -WindowStyle Minimized
    } else {
        Start-Process "cmd.exe" -ArgumentList "/c ngrok http 8000" -WindowStyle Minimized
    }

    $attempts = 0
    while (-not $ngrokUrl -and $attempts -lt 10) {
        Start-Sleep -Seconds 1
        $attempts++
        try {
            $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
        } catch {}
    }
}

# 2. Sync launch.json
if ($ngrokUrl) {
    Write-Host "[2/3] Live Tunnel active: $ngrokUrl" -ForegroundColor Green
    $launchJson = "$root\.vscode\launch.json"
    if (Test-Path $launchJson) {
        try {
            $json = Get-Content $launchJson -Raw | ConvertFrom-Json
            foreach ($config in $json.configurations) {
                $argsList = [System.Collections.Generic.List[string]]$config.args
                $existing = $argsList | Where-Object { $_ -like "--dart-define=BACKEND_URL=*" }
                foreach ($e in $existing) { $argsList.Remove($e) | Out-Null }
                $argsList.Add("--dart-define=BACKEND_URL=$ngrokUrl")
                $config.args = $argsList.ToArray()
            }
            $json | ConvertTo-Json -Depth 10 | Set-Content $launchJson -Encoding UTF8
        } catch {}
    }
} else {
    Write-Host "[2/3] ngrok tunnel not ready, continuing locally..." -ForegroundColor Yellow
}

# 3. Start uvicorn
Write-Host "[3/3] Starting FastAPI uvicorn server..." -ForegroundColor Green
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Backend running on: http://localhost:8000" -ForegroundColor White
if ($ngrokUrl) {
    Write-Host "  Live ngrok URL:     $ngrokUrl" -ForegroundColor Cyan
}
Write-Host "  Flutter app will automatically connect to this URL." -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

Set-Location "$root\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
