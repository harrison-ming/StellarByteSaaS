#!/bin/bash
# StellarByte Deployment Script for 107 Server - With Pre-built Image
# This script loads a pre-built Docker image and starts services
#
# Usage:
#   1. Build image locally and save: docker save stellarbyte:latest | gzip > stellarbyte-image.tar.gz
#   2. Transfer to 107: scp stellarbyte-image.tar.gz ming@192.168.1.107:/tmp/
#   3. Run this script on 107

set -e

echo "===== Starting StellarByte Deployment (Pre-built Image) ====="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Change to project directory
cd /Users/ming/Documents/host/StellarByte || exit 1

echo "[1/6] Pulling latest code from GitHub..."
git pull origin main
echo "✓ Code updated"
echo ""

echo "[2/6] Stopping existing containers..."
/usr/local/bin/docker compose down
echo "✓ Containers stopped"
echo ""

echo "[3/6] Loading Docker image from file..."
if [ -f "/tmp/stellarbyte-image.tar.gz" ]; then
  gunzip -c /tmp/stellarbyte-image.tar.gz | /usr/local/bin/docker load
  echo "✓ Image loaded: stellarbyte:latest"
  # Clean up the image file
  rm -f /tmp/stellarbyte-image.tar.gz
else
  echo "✗ Image file not found at /tmp/stellarbyte-image.tar.gz"
  echo "Please transfer the image first:"
  echo "  docker save stellarbyte:latest | gzip > stellarbyte-image.tar.gz"
  echo "  scp stellarbyte-image.tar.gz ming@192.168.1.107:/tmp/"
  exit 1
fi
echo ""

echo "[4/6] Starting services..."
/usr/local/bin/docker compose up -d
echo "✓ Services started"
echo ""

echo "[5/6] Waiting for services to initialize..."
sleep 15
echo ""

echo "[6/6] Checking container status..."
/usr/local/bin/docker compose ps
echo ""

echo "Running health checks..."
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
echo ""
