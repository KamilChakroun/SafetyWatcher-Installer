# ================================================================
#  Safety Watcher - Windows Installer
#  Requires: Docker Desktop installed and running, NVIDIA GPU
# ================================================================

$ErrorActionPreference = "Stop"
$DEST = "C:\SafetyWatcher"

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Safety Watcher - Installation" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# ── Check Docker ──────────────────────────────────────────────
Write-Host "[1/6] Checking Docker..." -ForegroundColor Yellow
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker Desktop not found." -ForegroundColor Red
    Write-Host "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    Write-Host "Then restart this installer."
    exit 1
}
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker is installed but not running." -ForegroundColor Red
    Write-Host "Start Docker Desktop from the taskbar and wait for it to fully load, then retry."
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

# ── Load Docker Images ────────────────────────────────────────
Write-Host "[3/6] Loading Docker images (this may take 10-15 minutes)..." -ForegroundColor Yellow
$images = Get-ChildItem "$PSScriptRoot\images\*.tar"
if ($images.Count -eq 0) {
    Write-Host "ERROR: No .tar files found in images\ folder." -ForegroundColor Red
    exit 1
}
foreach ($img in $images) {
    Write-Host "  Loading $($img.Name)..."
    docker load -i $img.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to load $($img.Name)" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  All images loaded" -ForegroundColor Green

# gateway and cammanager are identical to usermanager (same Dockerfile) - retag locally
docker tag ghcr.io/sirussnitch/safety-watcher-usermanager:latest ghcr.io/sirussnitch/safety-watcher-gateway:latest
docker tag ghcr.io/sirussnitch/safety-watcher-usermanager:latest ghcr.io/sirussnitch/safety-watcher-cammanager:latest
Write-Host "  gateway and cammanager tagged" -ForegroundColor Green

# ── Copy Project Files ────────────────────────────────────────
Write-Host "[4/6] Installing files to $DEST..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $DEST | Out-Null
New-Item -ItemType Directory -Force -Path "$DEST\monitoring" | Out-Null

Copy-Item "$PSScriptRoot\docker-compose.yaml"   $DEST -Force
Copy-Item "$PSScriptRoot\.env"                  $DEST -Force
Copy-Item "$PSScriptRoot\seed_admin.js"         $DEST -Force
Copy-Item "$PSScriptRoot\start.bat"             $DEST -Force
Copy-Item "$PSScriptRoot\stop.bat"              $DEST -Force
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
docker compose --project-name safety-watcher `
    -f docker-compose.yaml `
    -f monitoring/docker-compose.monitoring.yml `
    -f monitoring/docker-compose.nats-monitor.yml `
    up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: docker compose failed to start." -ForegroundColor Red
    Write-Host "Run: docker compose --project-name safety-watcher logs"
    exit 1
}
Write-Host "  Services started" -ForegroundColor Green

# ── Seed Admin User ───────────────────────────────────────────
Write-Host "[6/6] Creating admin user..." -ForegroundColor Yellow
Write-Host "  Waiting 20 seconds for MongoDB to be ready..."
Start-Sleep -Seconds 20
docker cp seed_admin.js safety-watcher-mongo_user-1:/seed_admin.js
docker exec safety-watcher-mongo_user-1 mongosh /seed_admin.js

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App:       http://localhost"
Write-Host "  Grafana:   http://localhost:3000  (admin / admin)"
Write-Host "  MinIO:     http://localhost:9001  (minioadmin / minioadmin)"
Write-Host "  Login:     admin / admin"
Write-Host ""
Write-Host "  To stop:   docker compose --project-name safety-watcher -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml down"
Write-Host "  To start:  docker compose --project-name safety-watcher -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml up -d"
Write-Host ""
Write-Host "  NOTE: Set MINIO_PRESIGN_ENDPOINT in .env to this machine's IP"
Write-Host "        if accessing from other devices on the network."
Write-Host ""
