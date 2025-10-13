#!/bin/bash
# StellarByte Deployment Script for 107 Server
# This script is executed by GitHub Actions on the 107 server

set -e

echo "===== Starting StellarByte Deployment ====="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Change to project directory
cd /Users/ming/Documents/host/StellarByte || exit 1

echo "[1/7] Pulling latest code from GitHub..."
git pull origin main
echo "✓ Code updated"
echo ""

echo "[2/7] Stopping existing containers..."
docker compose down
echo "✓ Containers stopped"
echo ""

echo "[3/7] Building new Docker image..."
docker build -f Dockerfile.dev -t stellarbyte:latest .
echo "✓ Image built: stellarbyte:latest"
echo ""

echo "[4/7] Starting services..."
docker compose up -d
echo "✓ Services started"
echo ""

echo "[5/7] Waiting for services to initialize..."
sleep 15
echo ""

echo "[6/7] Checking container status..."
docker compose ps
echo ""

echo "[7/7] Running health checks..."
HEALTH_CHECK_FAILED=false

# Check frontend (port 4100)
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:4100 | grep -q "200"; then
  echo "✓ Frontend service is healthy (port 4100)"
else
  echo "✗ Frontend service check failed (port 4100)"
  HEALTH_CHECK_FAILED=true
fi

# Check backend (port 4000)
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:4000 | grep -q "200\|404"; then
  echo "✓ Backend service is healthy (port 4000)"
else
  echo "✗ Backend service check failed (port 4000)"
  HEALTH_CHECK_FAILED=true
fi

echo ""

if [ "$HEALTH_CHECK_FAILED" = true ]; then
  echo "===== Deployment Completed with WARNINGS ====="
  echo "Some health checks failed. Please investigate."
  echo "Check logs with: docker compose logs -f"
  exit 1
else
  echo "===== Deployment Completed Successfully ====="
  echo "All services are running and healthy!"
fi

echo ""
echo "Access your application at:"
echo "  - Frontend: https://app.stellarbyte.ca"
echo "  - Backend API: http://localhost:4000"
echo ""
echo "View logs:"
echo "  docker compose logs -f postiz"
