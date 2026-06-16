@echo off
cd /d "%~dp0"
echo Starting Safety Watcher...
docker compose --project-name safetywatcher -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml up -d
if %ERRORLEVEL% neq 0 (
    echo.
    echo Failed to start. Check that Docker Desktop is running.
    pause
    exit /b 1
)
echo.
echo  Safety Watcher is running!
echo  App:      http://localhost
echo  Grafana:  http://localhost:3000  (admin / admin)
echo  MinIO:    http://localhost:9001  (minioadmin / minioadmin)
echo.
pause
