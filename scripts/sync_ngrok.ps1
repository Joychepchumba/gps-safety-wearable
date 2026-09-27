# Automatically finds or starts ngrok and updates .vscode/launch.json with the live URL
$ErrorActionPreference = "SilentlyContinue"
$root = Split-Path -Parent $PSScriptRoot
$launchJson = "$root\.vscode\launch.json"

$ngrokUrl = $null
try {
    $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
    $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
} catch {}

if (-not $ngrokUrl) {
    Write-Host "[ngrok] Not running on port 4040. Starting ngrok..." -ForegroundColor Yellow
    $npmNgrok = "$env:APPDATA\npm\node_modules\ngrok\bin\ngrok.exe"
    if (Test-Path $npmNgrok) {
        Start-Process $npmNgrok -ArgumentList "http 8000" -WindowStyle Minimized
    } else {
        Start-Process "cmd.exe" -ArgumentList "/c ngrok http 8000" -WindowStyle Minimized
    }
    
    $attempts = 0
    while (-not $ngrokUrl -and $attempts -lt 12) {
        Start-Sleep -Seconds 1
        $attempts++
        try {
            $tunnels = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $ngrokUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1).public_url
        } catch {}
    }
}

if ($ngrokUrl) {
    if (Test-Path $launchJson) {
        try {
            $json = Get-Content $launchJson -Raw | ConvertFrom-Json
            foreach ($config in $json.configurations) {
                $args = [System.Collections.Generic.List[string]]$config.args
                $existing = $args | Where-Object { $_ -like "--dart-define=BACKEND_URL=*" }
                foreach ($e in $existing) { $args.Remove($e) | Out-Null }
                $args.Add("--dart-define=BACKEND_URL=$ngrokUrl")
                $config.args = $args.ToArray()
            }
            $json | ConvertTo-Json -Depth 10 | Set-Content $launchJson -Encoding UTF8
        } catch {}
    }
    Write-Output $ngrokUrl
} else {
    Write-Output "http://localhost:8000"
}
