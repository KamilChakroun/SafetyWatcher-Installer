#!/bin/bash
# ================================================================
#  Safety Watcher — Linux (Ubuntu) Installer
#  Requires: Ubuntu 20.04/22.04/24.04, NVIDIA GPU + driver
# ================================================================

set -e
DEST="/opt/safety-watcher"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  Safety Watcher — Installation${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo ""

# ── Check root / sudo ─────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run with sudo.${NC}"
    echo "Run: sudo bash install-linux.sh"
    exit 1
fi
REAL_USER=${SUDO_USER:-$USER}

# ── Check/Install Docker Engine ───────────────────────────────
echo -e "${YELLOW}[1/6] Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo "  Docker not found. Installing Docker Engine..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    usermod -aG docker $REAL_USER
    echo -e "  ${GREEN}Docker installed${NC}"
else
    echo -e "  ${GREEN}Docker OK${NC}"
fi

# Ensure docker compose plugin works
if ! docker compose version &> /dev/null; then
    apt-get install -y docker-compose-plugin
fi

# ── Check/Install NVIDIA Container Toolkit ───────────────────
echo -e "${YELLOW}[2/6] Checking NVIDIA GPU...${NC}"
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}WARNING: nvidia-smi not found. NVIDIA driver may not be installed.${NC}"
    echo "  Inference requires an NVIDIA GPU with drivers installed."
    read -p "  Continue anyway? (y/N): " confirm
    [[ "$confirm" != "y" ]] && exit 1
else
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown")
    echo -e "  ${GREEN}GPU: $GPU_NAME${NC}"

    if ! dpkg -l | grep -q nvidia-container-toolkit; then
        echo "  Installing NVIDIA Container Toolkit..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
            gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update -qq
        apt-get install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        echo -e "  ${GREEN}NVIDIA Container Toolkit installed${NC}"
    else
        echo -e "  ${GREEN}NVIDIA Container Toolkit OK${NC}"
    fi
fi

# ── Load Docker Images ────────────────────────────────────────
echo -e "${YELLOW}[3/6] Loading Docker images (10-15 minutes)...${NC}"
TAR_FILES=("$SCRIPT_DIR"/images/*.tar)
if [[ ! -f "${TAR_FILES[0]}" ]]; then
    echo -e "${RED}ERROR: No .tar files found in images/ folder.${NC}"
    exit 1
fi
for f in "$SCRIPT_DIR"/images/*.tar; do
    echo "  Loading $(basename $f)..."
    docker load -i "$f"
done
echo -e "  ${GREEN}All images loaded${NC}"

# gateway and cammanager are identical to usermanager (same Dockerfile) — retag locally
docker tag ghcr.io/sirussnitch/safety-watcher-usermanager:latest ghcr.io/sirussnitch/safety-watcher-gateway:latest
docker tag ghcr.io/sirussnitch/safety-watcher-usermanager:latest ghcr.io/sirussnitch/safety-watcher-cammanager:latest
echo -e "  ${GREEN}gateway and cammanager tagged${NC}"

# ── Copy Project Files ────────────────────────────────────────
echo -e "${YELLOW}[4/6] Installing files to $DEST...${NC}"
mkdir -p "$DEST"
cp "$SCRIPT_DIR/docker-compose.yaml"  "$DEST/"
cp "$SCRIPT_DIR/.env"                 "$DEST/"
cp "$SCRIPT_DIR/seed_admin.js"        "$DEST/"
cp -r "$SCRIPT_DIR/models"            "$DEST/"
cp -r "$SCRIPT_DIR/monitoring"        "$DEST/"
cp "$SCRIPT_DIR/docker-compose.gpu.yml" "$DEST/"
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
echo "  Waiting 20 seconds for MongoDB to be ready..."
sleep 20
docker cp seed_admin.js safety-watcher-mongo_user-1:/seed_admin.js
docker exec safety-watcher-mongo_user-1 mongosh /seed_admin.js

# ── Create systemd service for auto-start on boot ─────────────
cat > /etc/systemd/system/safety-watcher.service << SVCEOF
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
systemctl enable safety-watcher
echo -e "  ${GREEN}Auto-start on boot enabled${NC}"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "  App:       http://localhost"
echo "  Grafana:   http://localhost:3000  (admin / admin)"
echo "  MinIO:     http://localhost:9001  (minioadmin / minioadmin)"
echo "  Login:     admin / admin"
echo ""
echo "  To stop:   sudo systemctl stop safety-watcher"
echo "  To start:  sudo systemctl start safety-watcher"
echo "  To status: sudo systemctl status safety-watcher"
echo ""
echo "  NOTE: Set MINIO_PRESIGN_ENDPOINT in $DEST/.env to this"
echo "        machine's IP if accessing from other devices."
echo ""
