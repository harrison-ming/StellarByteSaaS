# StellarByte Deployment Guide

Complete guide for deploying StellarByte to production.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)
- [Cloudflare Tunnel Configuration](#cloudflare-tunnel-configuration)
- [GitHub Actions Setup](#github-actions-setup)
- [Manual Deployment](#manual-deployment)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### On 107 Server

- ✅ Docker & Docker Compose installed
- ✅ Git installed
- ✅ SSH access configured
- ✅ Cloudflared installed and configured
- ✅ Sufficient disk space (>20GB recommended)

### For CI/CD

- ✅ GitHub repository access
- ✅ SSH key pair for GitHub Actions

---

## First-Time Setup

### Step 1: Clone Repository on 107

```bash
ssh ming@192.168.1.107
cd /Users/ming/Documents/host/
git clone https://github.com/harrison-ming/StellarByteSaaS.git StellarByte
cd StellarByte
```

### Step 2: Configure Environment

```bash
# Copy template
cp .env.example .env

# Edit with your actual values
nano .env
```

**Required values**:
- `POSTGRES_PASSWORD` - Strong password for database
- `JWT_SECRET` - Random 32+ character string
- `CLOUDFLARE_*` - Your R2 storage credentials
- `YOUTUBE_CLIENT_ID/SECRET` - Google OAuth credentials

### Step 3: Build Docker Image

```bash
docker build -f Dockerfile.dev -t stellarbyte:latest .
```

This will take 5-10 minutes on first build.

### Step 4: Start Services

```bash
docker compose up -d
```

### Step 5: Verify Services

```bash
# Check container status
docker compose ps

# Check logs
docker compose logs -f postiz

# Test frontend
curl http://localhost:4100

# Test backend
curl http://localhost:4000
```

---

## Cloudflare Tunnel Configuration

### Update Tunnel Configuration

Edit `~/.cloudflared/config.yml` on 107:

```yaml
tunnel: 35398c78-7890-4684-8dc4-e4b246a6d53a
credentials-file: /Users/ming/.cloudflared/35398c78-7890-4684-8dc4-e4b246a6d53a.json

ingress:
  - hostname: freshrss.stellarview.ca
    service: http://localhost:8080
  - hostname: server.stellarview.ca
    service: http://localhost:80
  - hostname: mysql.stellarview.ca
    service: tcp://localhost:3306
  - hostname: app.stellarbyte.ca      # ← NEW
    service: http://localhost:4100
  - service: http_status:404
```

### Create DNS Record

**Option A: Via Cloudflare Dashboard**
1. Go to Cloudflare Dashboard → DNS
2. Add CNAME record:
   - Name: `app`
   - Target: `35398c78-7890-4684-8dc4-e4b246a6d53a.cfargotunnel.com`
   - Proxy: Enabled

**Option B: Via CLI**
```bash
cloudflared tunnel route dns stellarbyte-tunnel app.stellarbyte.ca
```

### Restart Tunnel

Using the existing `start_dev_env.sh` script:

```bash
cd /Users/ming/Documents/host/StellarView
bash bin/start_dev_env.sh --supervisor
```

Or restart manually:
```bash
# Find tunnel process
ps aux | grep cloudflared

# Kill and restart
pkill cloudflared
cloudflared tunnel run &
```

---

## GitHub Actions Setup

### Step 1: Generate SSH Key for GitHub Actions

On your local machine:

```bash
# Generate new key pair
ssh-keygen -t ed25519 -C "github-actions@stellarbyte" -f ~/.ssh/github_actions_stellarbyte

# Copy public key to 107
ssh-copy-id -i ~/.ssh/github_actions_stellarbyte.pub ming@192.168.1.107

# Test connection
ssh -i ~/.ssh/github_actions_stellarbyte ming@192.168.1.107 "echo 'Connection successful'"
```

### Step 2: Add GitHub Secrets

Go to: https://github.com/harrison-ming/StellarByteSaaS/settings/secrets/actions

Add these secrets:

1. **SSH_HOST**
   ```
   192.168.1.107
   ```

2. **SSH_USER**
   ```
   ming
   ```

3. **SSH_PRIVATE_KEY**
   ```
   # Paste contents of ~/.ssh/github_actions_stellarbyte
   cat ~/.ssh/github_actions_stellarbyte
   # Copy entire output including:
   # -----BEGIN OPENSSH PRIVATE KEY-----
   # ...
   # -----END OPENSSH PRIVATE KEY-----
   ```

### Step 3: Test GitHub Actions

```bash
# Make a small change
echo "# Test" >> README.md

# Commit and push
git add README.md
git commit -m "Test: Trigger deployment"
git push origin main
```

Check workflow status at:
https://github.com/harrison-ming/StellarByteSaaS/actions

---

## Manual Deployment

### Full Deployment

```bash
ssh ming@192.168.1.107
cd /Users/ming/Documents/host/StellarByte
bash deploy-to-107.sh
```

### Partial Updates

**Update code only** (no rebuild):
```bash
git pull origin main
docker compose restart postiz
```

**Rebuild image** (after dependency changes):
```bash
docker compose down
docker build -f Dockerfile.dev -t stellarbyte:latest .
docker compose up -d
```

**View logs**:
```bash
docker compose logs -f postiz
```

---

## Backup & Restore

### Manual Backup

#### Backup Database

```bash
# Create backup
docker exec stellarbyte-postgres pg_dump -U stellarbyte stellarbyte > \
  ~/backups/stellarbyte_$(date +%Y%m%d_%H%M%S).sql

# Compress
gzip ~/backups/stellarbyte_$(date +%Y%m%d_%H%M%S).sql
```

#### Backup Redis (Optional)

```bash
# Redis auto-saves to disk, just copy the file
docker cp stellarbyte-redis:/data/dump.rdb \
  ~/backups/redis_$(date +%Y%m%d_%H%M%S).rdb
```

#### Backup Environment Configuration

```bash
# Backup .env to secure location
cp /Users/ming/Documents/host/StellarByte/.env \
  ~/backups/env_$(date +%Y%m%d_%H%M%S).backup
```

#### Copy Backups to Local Machine

```bash
# On local machine
scp ming@192.168.1.107:~/backups/stellarbyte_*.sql.gz ~/local_backups/
```

### Restore from Backup

#### Restore Database

```bash
# Stop application
docker compose stop postiz

# Restore database
gunzip < ~/backups/stellarbyte_20250113.sql.gz | \
  docker exec -i stellarbyte-postgres psql -U stellarbyte stellarbyte

# Restart
docker compose start postiz
```

#### Restore Redis

```bash
docker compose stop redis
docker cp ~/backups/redis_20250113.rdb stellarbyte-redis:/data/dump.rdb
docker compose start redis
```

### Automated Backup Script

Create `~/bin/backup-stellarbyte.sh`:

```bash
#!/bin/bash
BACKUP_DIR=~/backups/stellarbyte
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
docker exec stellarbyte-postgres pg_dump -U stellarbyte stellarbyte | \
  gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Backup Redis
docker cp stellarbyte-redis:/data/dump.rdb $BACKUP_DIR/redis_$DATE.rdb

# Backup .env
cp /Users/ming/Documents/host/StellarByte/.env $BACKUP_DIR/env_$DATE.backup

# Keep only last 7 days
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +7 -delete
find $BACKUP_DIR -name "redis_*.rdb" -mtime +7 -delete

echo "Backup completed: $DATE"
```

Make executable and schedule:
```bash
chmod +x ~/bin/backup-stellarbyte.sh

# Add to crontab (daily at 2 AM)
crontab -e
# Add line:
0 2 * * * ~/bin/backup-stellarbyte.sh >> ~/logs/backup.log 2>&1
```

---

## Troubleshooting

### Issue: Container Won't Start

**Check logs**:
```bash
docker compose logs postiz
```

**Common causes**:
- Database connection failed → Check `DATABASE_URL` in `.env`
- Port already in use → Check with `lsof -ti:4100`
- Missing environment variables → Compare `.env` with `.env.example`

**Solution**:
```bash
docker compose down
docker compose up -d
docker compose logs -f
```

### Issue: Health Check Failed

**Test services**:
```bash
# Frontend
curl -I http://localhost:4100

# Backend
curl -I http://localhost:4000

# Database
docker exec stellarbyte-postgres psql -U stellarbyte -c "SELECT 1"
```

**Restart services**:
```bash
docker compose restart
```

### Issue: GitHub Actions Deployment Fails

**Check workflow logs**:
https://github.com/harrison-ming/StellarByteSaaS/actions

**Common causes**:
- SSH connection failed → Verify SSH key in GitHub Secrets
- Permission denied → Check file permissions on 107
- Build failed → Check for code errors

**Test SSH connection manually**:
```bash
ssh -i ~/.ssh/github_actions_stellarbyte ming@192.168.1.107
```

### Issue: Cloudflare Tunnel Not Working

**Check tunnel status**:
```bash
# On 107
ps aux | grep cloudflared
```

**Restart tunnel**:
```bash
cd /Users/ming/Documents/host/StellarView
bash bin/start_dev_env.sh --restart-supervisor
```

**Test tunnel**:
```bash
curl https://app.stellarbyte.ca
```

### Issue: Database Migration Failed

**Manual migration**:
```bash
docker exec stellarbyte-app pnpm prisma migrate deploy
```

### Issue: Out of Disk Space

**Check disk usage**:
```bash
df -h
docker system df
```

**Clean up**:
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Clean build cache
docker builder prune
```

---

## Monitoring

### Check Service Health

```bash
# Container status
docker compose ps

# Resource usage
docker stats

# Disk usage
docker system df

# Logs
docker compose logs --tail=100 postiz
```

### Application Logs

```bash
# Real-time logs
docker compose logs -f postiz

# Last 100 lines
docker compose logs --tail=100 postiz

# Search logs
docker compose logs postiz | grep ERROR
```

---

## Updating

### Update from GitHub

```bash
cd /Users/ming/Documents/host/StellarByte
git pull origin main
bash deploy-to-107.sh
```

### Update Dependencies

```bash
# Inside container
docker exec -it stellarbyte-app pnpm install

# Or rebuild image
docker compose down
docker build -f Dockerfile.dev -t stellarbyte:latest .
docker compose up -d
```

---

## Security Best Practices

1. ✅ Never commit `.env` to Git
2. ✅ Use strong passwords (>20 characters)
3. ✅ Rotate JWT_SECRET periodically
4. ✅ Keep Docker images updated
5. ✅ Regular backups (automated)
6. ✅ Monitor logs for suspicious activity
7. ✅ Use SSH keys, not passwords
8. ✅ Limit SSH access to specific IPs if possible

---

## Support

- 📧 Email: support@stellarbyte.ca
- 🐛 Issues: https://github.com/harrison-ming/StellarByteSaaS/issues
- 📚 Documentation: https://github.com/harrison-ming/StellarByteSaaS

---

*Last Updated: 2025-01-13*
