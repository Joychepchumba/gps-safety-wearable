# ==========================================================
# SafeLink Backend Auto-Runner
# Automatically launches ngrok with your static domain
# ==========================================================
$ErrorActionPreference = "SilentlyContinue"
$root = $PSScriptRoot
if (Test-Path "$PSScriptRoot\..\backend\app\main.py") {
    $root = (Resolve-Path "$PSScriptRoot\..").Path
}

$staticDomain = "unpaved-coherent-encroach.ngrok-free.dev"
$staticUrl = "https://$staticDomain"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SafeLink Backend Server + Static ngrok Tunnel          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check existing tunnel on port 4040
Write-Host "[1/3] Checking ngrok tunnel..." -ForegroundColor Yellow
$currentUrl = $null
try {
    $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
    $currentUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
} catch {}

# If an old ngrok process is running with a different URL, kill it
if ($currentUrl -and -not $currentUrl.Contains($staticDomain)) {
    Write-Host "      Detected old random tunnel ($currentUrl). Stopping old process..." -ForegroundColor Yellow
    Stop-Process -Name "ngrok" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $currentUrl = $null
}

# If ngrok is not running with the static domain, start it
if (-not $currentUrl) {
    Write-Host "      Starting ngrok on port 8000 with domain: $staticDomain" -ForegroundColor DarkGray
    $npmNgrok = "$env:APPDATA\npm\node_modules\ngrok\bin\ngrok.exe"
    $ngrokArgs = "http 8000 --url=$staticDomain"
    if (Test-Path $npmNgrok) {
        Start-Process $npmNgrok -ArgumentList $ngrokArgs -WindowStyle Minimized
    } else {
        Start-Process "cmd.exe" -ArgumentList "/c ngrok $ngrokArgs" -WindowStyle Minimized
    }

    $attempts = 0
    while (-not $currentUrl -and $attempts -lt 8) {
        Start-Sleep -Seconds 1
        $attempts++
        try {
            $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $currentUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
        } catch {}
    }
}

$ngrokUrl = if ($currentUrl) { $currentUrl } else { $staticUrl }
Write-Host "      Live Static Tunnel: $ngrokUrl" -ForegroundColor Green

# 2. Sync launch.json
Write-Host "[2/3] Synchronizing configurations with $ngrokUrl..." -ForegroundColor Yellow
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

# 3. Start uvicorn
Write-Host "[3/3] Starting FastAPI uvicorn server..." -ForegroundColor Green
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Backend running on: http://localhost:8000" -ForegroundColor White
Write-Host "  Live Static URL:    $ngrokUrl" -ForegroundColor Cyan
Write-Host "  Flutter app will automatically connect to this URL." -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

Set-Location "$root\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
