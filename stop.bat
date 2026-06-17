@echo off
cd /d "%~dp0"
echo Stopping Safety Watcher...
docker compose -f docker-compose.yaml -f monitoring/docker-compose.monitoring.yml -f monitoring/docker-compose.nats-monitor.yml down
if %ERRORLEVEL% neq 0 (
    echo.
    echo Failed to stop. Check that Docker Desktop is running.
    pause
    exit /b 1
)
echo.
echo Safety Watcher stopped.
echo.
pause
