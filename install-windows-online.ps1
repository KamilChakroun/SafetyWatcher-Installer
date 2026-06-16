# ================================================================
#  Safety Watcher - Windows Installer (Online)
#  Automatically detects internet and pulls or loads images.
# ================================================================

$ErrorActionPreference = "Stop"
$DEST = "C:\SafetyWatcher"
$GHCR = "ghcr.io/sirussnitch"

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Safety Watcher - Installation" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# ── Check Docker ──────────────────────────────────────────────
Write-Host "[1/6] Checking Docker..." -ForegroundColor Yellow
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker Desktop not found." -ForegroundColor Red
    Write-Host "Install it from https://www.docker.com/products/docker-desktop/"
    exit 1
}
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker is installed but not running." -ForegroundColor Red
    Write-Host "Start Docker Desktop and wait for it to fully load, then retry."
    exit 1
}
Write-Host "  Docker OK" -ForegroundColor Green

# ── Check NVIDIA GPU ──────────────────────────────────────────
Write-Host "[2/6] Checking NVIDIA GPU..." -ForegroundColor Yellow
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: nvidia-smi not found. GPU inference may not work." -ForegroundColor Yellow
    Write-Host "  Continuing installation..." -ForegroundColor Yellow
} else {
    $gpuInfo = nvidia-smi --query-gpu=name --format=csv,noheader 2>$null
    Write-Host "  GPU: $gpuInfo" -ForegroundColor Green
}

# ── Detect Internet ───────────────────────────────────────────
Write-Host "[3/6] Detecting internet connectivity..." -ForegroundColor Yellow
$online = $false
try {
    $response = Invoke-WebRequest -Uri "https://ghcr.io" -TimeoutSec 5 -UseBasicParsing
    $online = $true
} catch {}

if (-not $online) {
    Write-Host "ERROR: No internet connection detected." -ForegroundColor Red
    Write-Host "This installer requires internet access to pull images from ghcr.io."
    Write-Host "Please connect to the internet and try again."
    exit 1
}

Write-Host "  Internet available - pulling images from ghcr.io" -ForegroundColor Green
Write-Host "  (Assuming already logged in via: docker login ghcr.io)" -ForegroundColor Yellow
Write-Host "  Pulling images (takes 5-15 min on first run)..."
$pullImages = @(
    "$GHCR/safety-watcher-frontend:latest",
    "$GHCR/safety-watcher-gateway:latest",
    "$GHCR/safety-watcher-usermanager:latest",
    "$GHCR/safety-watcher-cammanager:latest",
    "$GHCR/safety-watcher-inference:latest",
    "$GHCR/safety-watcher-reader:latest",
    "$GHCR/safety-watcher-streamer:latest",
    "$GHCR/safety-watcher-historymanager:latest",
    "mongo:8",
    "nats:latest",
    "minio/minio:latest",
    "prom/prometheus:latest",
    "grafana/grafana:latest",
    "grafana/loki:latest",
    "grafana/promtail:latest",
    "gcr.io/cadvisor/cadvisor:latest",
    "natsio/prometheus-nats-exporter:latest"
)
foreach ($img in $pullImages) {
    Write-Host "  Pulling $img..."
    docker pull $img
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to pull $img. Check your internet connection and PAT." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  Images ready" -ForegroundColor Green

# ── Copy Project Files ────────────────────────────────────────
Write-Host "[4/6] Installing files to $DEST..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $DEST | Out-Null
Copy-Item "$PSScriptRoot\docker-compose.yaml"   $DEST -Force
Copy-Item "$PSScriptRoot\.env"                  $DEST -Force
Copy-Item "$PSScriptRoot\seed_admin.js"         $DEST -Force
Copy-Item -Recurse "$PSScriptRoot\models"       $DEST -Force
Copy-Item -Recurse "$PSScriptRoot\monitoring"   $DEST -Force
Write-Host "  Files copied" -ForegroundColor Green

# ── Start Services ────────────────────────────────────────────
Write-Host "[5/6] Starting Safety Watcher..." -ForegroundColor Yellow
Set-Location $DEST
docker network inspect safety-watcher_default | Out-Null
if ($LASTEXITCODE -ne 0) {
    docker network create safety-watcher_default | Out-Null
    Write-Host "  Network created" -ForegroundColor Green
} else {
    Write-Host "  Network already exists" -ForegroundColor Green
}
docker compose `
    -f docker-compose.yaml `
    -f monitoring/docker-compose.monitoring.yml `
    -f monitoring/docker-compose.nats-monitor.yml `
    up -d
Write-Host "  Services started" -ForegroundColor Green

# ── Seed Admin User ───────────────────────────────────────────
Write-Host "[6/6] Creating admin user..." -ForegroundColor Yellow
Write-Host "  Waiting 20 seconds for MongoDB..."
Start-Sleep -Seconds 20
docker cp seed_admin.js safety-watcher-mongo_user-1:/seed_admin.js
docker exec safety-watcher-mongo_user-1 mongosh /seed_admin.js

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App:      http://localhost"
Write-Host "  Grafana:  http://localhost:3000  (admin / admin)"
Write-Host "  MinIO:    http://localhost:9001  (minioadmin / minioadmin)"
Write-Host "  Login:    admin / admin"
Write-Host ""
Write-Host "  NOTE: Set MINIO_PRESIGN_ENDPOINT in .env to this machine's IP"
Write-Host "        if accessing from other devices on the network."
Write-Host ""
