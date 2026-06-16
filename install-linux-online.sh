#!/bin/bash
# ================================================================
#  Safety Watcher — Linux Installer (Online / Offline)
#  Automatically detects internet and pulls or loads images.
# ================================================================

set -e
DEST="/opt/safetywatcher"
GHCR="ghcr.io/sirussnitch"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  Safety Watcher — Installation${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo ""

[[ $EUID -ne 0 ]] && echo -e "${RED}Run with sudo.${NC}" && exit 1
REAL_USER=${SUDO_USER:-$USER}

# ── Check/Install Docker ──────────────────────────────────────
echo -e "${YELLOW}[1/6] Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo "  Installing Docker Engine..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    usermod -aG docker $REAL_USER
fi
echo -e "  ${GREEN}Docker OK${NC}"

# ── Check NVIDIA GPU + Toolkit ────────────────────────────────
echo -e "${YELLOW}[2/6] Checking NVIDIA GPU...${NC}"
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown")
    echo -e "  ${GREEN}GPU: $GPU_NAME${NC}"
    if ! dpkg -l | grep -q nvidia-container-toolkit; then
        echo "  Installing NVIDIA Container Toolkit..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
            gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update -qq && apt-get install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
    fi
else
    echo -e "${RED}WARNING: nvidia-smi not found.${NC}"
    read -p "  Continue anyway? (y/N): " confirm
    [[ "$confirm" != "y" ]] && exit 1
fi

# ── Detect Internet ───────────────────────────────────────────
echo -e "${YELLOW}[3/6] Detecting internet connectivity...${NC}"
ONLINE=false
if curl -fsSL --connect-timeout 5 https://ghcr.io > /dev/null 2>&1; then
    ONLINE=true
fi

if ! $ONLINE; then
    echo -e "${RED}ERROR: No internet connection detected.${NC}"
    echo "This installer requires internet access to pull images from ghcr.io."
    echo "Please connect to the internet and try again."
    exit 1
fi

echo -e "  ${GREEN}Internet available — pulling from ghcr.io${NC}"

read -p "  GitHub PAT (read:packages) — press Enter if already logged in: " PAT
if [[ -n "$PAT" ]]; then
    read -p "  GitHub username: " GHUSER
    echo "$PAT" | sudo -u $REAL_USER docker login ghcr.io -u "$GHUSER" --password-stdin
fi

PULL_IMAGES=(
    "$GHCR/safety-watcher-frontend:latest"
    "$GHCR/safety-watcher-gateway:latest"
    "$GHCR/safety-watcher-usermanager:latest"
    "$GHCR/safety-watcher-cammanager:latest"
    "$GHCR/safety-watcher-inference:latest"
    "$GHCR/safety-watcher-reader:latest"
    "$GHCR/safety-watcher-streamer:latest"
    "$GHCR/safety-watcher-historymanager:latest"
    "mongo:8"
    "nats:latest"
    "minio/minio:latest"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "grafana/loki:latest"
    "grafana/promtail:latest"
    "gcr.io/cadvisor/cadvisor:latest"
    "natsio/prometheus-nats-exporter:latest"
)
for img in "${PULL_IMAGES[@]}"; do
    echo "  Pulling $img..."
    sudo -u $REAL_USER docker pull "$img"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to pull $img. Check internet connection and PAT.${NC}"
        exit 1
    fi
done
echo -e "  ${GREEN}Images ready${NC}"

# ── Copy Project Files ────────────────────────────────────────
echo -e "${YELLOW}[4/6] Installing files to $DEST...${NC}"
mkdir -p "$DEST"
cp "$SCRIPT_DIR/docker-compose.yaml" "$DEST/"
cp "$SCRIPT_DIR/.env"                "$DEST/"
cp "$SCRIPT_DIR/seed_admin.js"       "$DEST/"
cp -r "$SCRIPT_DIR/models"           "$DEST/"
cp -r "$SCRIPT_DIR/monitoring"       "$DEST/"
chown -R $REAL_USER:$REAL_USER "$DEST"
echo -e "  ${GREEN}Files copied${NC}"

# ── Start Services ────────────────────────────────────────────
echo -e "${YELLOW}[5/6] Starting Safety Watcher...${NC}"
cd "$DEST"
sudo -u $REAL_USER docker compose \
    -f docker-compose.yaml \
    -f monitoring/docker-compose.monitoring.yml \
    -f monitoring/docker-compose.nats-monitor.yml \
    up -d
echo -e "  ${GREEN}Services started${NC}"

# ── Seed Admin User ───────────────────────────────────────────
echo -e "${YELLOW}[6/6] Creating admin user...${NC}"
sleep 20
docker cp seed_admin.js safety-watcher-mongo_user-1:/seed_admin.js
docker exec safety-watcher-mongo_user-1 mongosh /seed_admin.js

# ── Systemd auto-start ────────────────────────────────────────
cat > /etc/systemd/system/safetywatcher.service << SVCEOF
[Unit]
Description=Safety Watcher
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DEST
ExecStart=/usr/bin/docker compose -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml down
User=$REAL_USER

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable safetywatcher
echo -e "  ${GREEN}Auto-start on boot enabled${NC}"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "  App:      http://localhost"
echo "  Grafana:  http://localhost:3000  (admin / admin)"
echo "  MinIO:    http://localhost:9001  (minioadmin / minioadmin)"
echo "  Login:    admin / admin"
echo ""
echo "  To stop:   sudo systemctl stop safetywatcher"
echo "  To start:  sudo systemctl start safetywatcher"
echo ""
echo "  NOTE: Set MINIO_PRESIGN_ENDPOINT in $DEST/.env to this"
echo "        machine's IP if accessing from other devices."
echo ""
