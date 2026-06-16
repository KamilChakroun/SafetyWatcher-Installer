# ================================================================
#  Safety Watcher — Save all Docker images for offline installer
#  Run this on a machine that has pulled all images from ghcr.io
#  Requires: ~9GB free disk space
# ================================================================

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "images" | Out-Null

$images = @(
    # App images
    @{ name = "ghcr.io/sirussnitch/safety-watcher-frontend:latest";       file = "images/frontend.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-gateway:latest";        file = "images/gateway.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-usermanager:latest";    file = "images/usermanager.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-cammanager:latest";     file = "images/cammanager.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-inference:latest";      file = "images/inference.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-reader:latest";         file = "images/reader.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-streamer:latest";       file = "images/streamer.tar" },
    @{ name = "ghcr.io/sirussnitch/safety-watcher-historymanager:latest"; file = "images/historymanager.tar" },
    # Infrastructure
    @{ name = "mongo:8";                                                   file = "images/mongo.tar" },
    @{ name = "nats:latest";                                               file = "images/nats.tar" },
    @{ name = "minio/minio:latest";                                        file = "images/minio.tar" },
    # Monitoring
    @{ name = "prom/prometheus:latest";                                    file = "images/prometheus.tar" },
    @{ name = "grafana/grafana:latest";                                    file = "images/grafana.tar" },
    @{ name = "grafana/loki:latest";                                       file = "images/loki.tar" },
    @{ name = "grafana/promtail:latest";                                   file = "images/promtail.tar" },
    @{ name = "gcr.io/cadvisor/cadvisor:latest";                          file = "images/cadvisor.tar" },
    @{ name = "natsio/prometheus-nats-exporter:latest";                   file = "images/nats-exporter.tar" }
)

$total = $images.Count
$i = 0
foreach ($img in $images) {
    $i++
    Write-Host "[$i/$total] Saving $($img.name)..."
    docker save $img.name -o $img.file
}

$size = (Get-ChildItem images/*.tar | Measure-Object -Property Length -Sum).Sum / 1GB
Write-Host ""
Write-Host "Done. Total size: $([math]::Round($size, 1)) GB"
Write-Host "Copy the entire installer folder to a USB drive or network share."
