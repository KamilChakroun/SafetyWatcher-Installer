================================================================
  Safety Watcher — Offline Installer
================================================================

CONTENTS
--------
install-windows.ps1        Windows installer script (offline)
install-windows-online.ps1 Windows installer script (online, pulls from ghcr.io)
install-linux.sh           Ubuntu/Linux installer script (offline)
install-linux-online.sh    Ubuntu/Linux installer script (online, pulls from ghcr.io)
save-images.ps1            Script to re-save images (for updates)
docker-compose.yaml        Application service definitions
.env                       Environment configuration
seed_admin.js              Creates the initial admin user
models/                    YOLO ONNX model file
monitoring/                Grafana/Prometheus/Loki configuration
images/                    Docker images (~11GB, 17 files)

REQUIREMENTS
------------
- NVIDIA GPU (required for fire/smoke detection inference)
- Windows 10/11 or Ubuntu 20.04/22.04/24.04
- 16GB RAM minimum, 32GB recommended
- 30GB free disk space (includes MinIO detection frame storage)
- For Windows: Docker Desktop installed and running

INSTALLATION
------------
Windows:
  1. Install Docker Desktop if not already installed
  2. Start Docker Desktop and wait for it to fully load
  3. Right-click install-windows.ps1 → Run with PowerShell
     (or: powershell -ExecutionPolicy Bypass -File install-windows.ps1)

Linux (Ubuntu):
  1. Open terminal in this folder
  2. Run: sudo bash install-linux.sh
  3. If Docker was just installed, log out and back in after

ACCESS
------
  Application:  http://localhost
  Monitoring:   http://localhost:3000  (admin / admin)
  MinIO:        http://localhost:9001  (minioadmin / minioadmin)
  Default login: admin / admin
  (Change password after first login)

MULTI-DEVICE / NETWORK ACCESS
------------------------------
  If the application will be accessed from other machines on the
  network, set MINIO_PRESIGN_ENDPOINT in .env to the server's
  IP address (e.g. 192.168.1.10:9000) before starting.
  History page images are loaded directly from MinIO by the
  browser — the hostname must be reachable by the client device.

UPDATING
--------
  1. Pull new images on a machine with internet access
  2. Run save-images.ps1 to save updated images
  3. Copy new images/ folder to client machine
  4. Run installer again (it skips already-running steps)
  Or simply: docker load -i images/<updated-image>.tar
             docker compose up -d

CAMERA SETUP
------------
  Add cameras via the web interface at http://localhost
  Use the RTSP URL format for your NVR brand:

  Hikvision:  rtsp://user:pass@<NVR-IP>:554/Streaming/Channels/101
  Dahua:      rtsp://user:pass@<NVR-IP>:554/cam/realmonitor?channel=1&subtype=0
  Axis:       rtsp://user:pass@<NVR-IP>:554/axis-media/media.amp

  Test the RTSP URL in VLC before adding to Safety Watcher.
================================================================
