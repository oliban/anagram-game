# 🚀 Wordshelf Deployment Guide

This guide covers deployment procedures for all environments: Local, Staging (Pi), and Production (AWS).

## 📋 Table of Contents
- [Quick Start](#quick-start)
- [Local Development](#local-development)
- [Pi Staging Deployment](#pi-staging-deployment)
- [AWS Production Deployment](#aws-production-deployment)
- [Architecture Overview](#architecture-overview)
- [Troubleshooting](#troubleshooting)

## Quick Start

```bash
# Local Development
./build_multi_sim.sh local

# Pi Staging (Complete deployment)
./scripts/deploy-staging.sh

# AWS Production
./build_multi_sim.sh aws
```

## Local Development

### Prerequisites
- Docker Desktop installed and running
- Xcode 15+ with iOS 17.2+ SDK
- Local network access (192.168.x.x)

### Starting Services

```bash
# Start all backend services
docker-compose -f docker-compose.services.yml up -d

# Verify services are healthy
docker-compose -f docker-compose.services.yml ps

# Check logs if needed
docker-compose -f docker-compose.services.yml logs -f
```

### Building iOS Apps

```bash
# Build and deploy to iPhone 15 simulators
./build_multi_sim.sh local

# Force clean build (if cache issues)
./build_multi_sim.sh local --clean
```

### Service URLs (Local)
- Game Server: `http://192.168.1.188:3000`
- Web Dashboard: `http://192.168.1.188:3001`
- Admin Service: `http://192.168.1.188:3003`

## Pi Staging Deployment

### Overview
The Pi staging environment uses Cloudflare Tunnel for public access. The tunnel URL changes on each server restart, and our deployment scripts handle this automatically.

### Prerequisites
- SSH access to Pi: `pi@192.168.1.222`
- Cloudflare tunnel service configured on Pi
- Docker and docker-compose installed on Pi

### Automated Deployment

One command to deploy everything:

```bash
./scripts/deploy-staging.sh
```

### What the Script Does

1. **Sync Code**: Copies latest code to Pi
2. **Stop Services**: Cleanly shuts down existing containers
3. **Restart Tunnel**: Gets new Cloudflare tunnel URL
4. **Start Services**: Launches containers with `DYNAMIC_TUNNEL_URL` set
5. **Build iOS Apps**: Configures apps with tunnel URL
6. **Deploy to Simulators**: Installs on iPhone 15 devices

### Manual Deployment Steps

If you need to deploy manually:

```bash
# 1. Sync code to Pi
rsync -avz --exclude 'node_modules' --exclude '.git' \
  ./services/ pi@192.168.1.222:~/anagram-game/services/
rsync -avz ./docker-compose.services.yml \
  pi@192.168.1.222:~/anagram-game/

# 2. SSH to Pi
ssh pi@192.168.1.222

# 3. On Pi: Restart services with tunnel URL
cd ~/anagram-game
docker-compose -f docker-compose.services.yml down
sudo systemctl restart cloudflare-tunnel
sleep 5
TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt)
echo "DYNAMIC_TUNNEL_URL=$TUNNEL_URL" >> .env
docker-compose -f docker-compose.services.yml up -d --build

# 4. Back on local: Build iOS apps
export PI_TUNNEL_URL="$TUNNEL_URL"
./build_multi_sim.sh staging
```

### Tunnel URL Management

The Cloudflare tunnel URL is dynamic and stored in:
- On Pi: `~/cloudflare-tunnel-url.txt`
- In Docker: Passed as `DYNAMIC_TUNNEL_URL` environment variable
- In iOS: Configured via `NetworkConfiguration.swift` during build

### Service URLs (Staging)
- Tunnel URL: `https://*.trycloudflare.com` (changes on restart)
- All services accessed through tunnel URL

## AWS Production Deployment

### Prerequisites
- AWS CLI configured
- ECS cluster access
- Production environment variables set

### Server Deployment

See `docs/aws-production-server-management.md` for detailed AWS deployment instructions.

### iOS App Deployment

```bash
# Build for AWS production
./build_multi_sim.sh aws

# Deploys to iPhone SE simulator
# Uses stable AWS load balancer URL
```

### Service URLs (Production)
- Load Balancer: `http://anagram-staging-alb-*.eu-west-1.elb.amazonaws.com`

## Architecture Overview

### Consolidated Services (as of August 2025)

```
┌─────────────────────────────────────────┐
│           iOS Apps (SwiftUI)            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│      Game Server (Port 3000)            │
│  • Core API + WebSocket                 │
│  • Contribution System (Consolidated)    │
│  • Player Management                    │
│  • Phrase Operations                    │
└─────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│   Web    │ │  Admin   │ │PostgreSQL│
│Dashboard │ │ Service  │ │    DB    │
│  (3001)  │ │  (3003)  │ │  (5432)  │
└──────────┘ └──────────┘ └──────────┘
```

### Key Changes
- **Link Generator Service**: Eliminated and consolidated into Game Server
- **Contribution System**: Now integrated directly in Game Server at `/api/contribution/*`
- **Simplified Architecture**: Reduced from 4 to 3 microservices

## Environment Variables

### Critical Variables for Deployment

```bash
# Database
DB_NAME=anagram_game
DB_USER=postgres
DB_PASSWORD=postgres

# Service Ports
GAME_SERVER_PORT=3000
WEB_DASHBOARD_PORT=3001
ADMIN_SERVICE_PORT=3003

# Security
ADMIN_API_KEY=your-admin-key
SECURITY_RELAXED=false  # true for dev only

# Staging Only
DYNAMIC_TUNNEL_URL=https://your-tunnel.trycloudflare.com
```

### Docker Compose Configuration

The `docker-compose.services.yml` file now includes:
```yaml
environment:
  - DYNAMIC_TUNNEL_URL=${DYNAMIC_TUNNEL_URL}  # For contribution links
```

## Troubleshooting

### Common Issues

#### 1. Old IP in Contribution Links
**Problem**: Links show `192.168.1.133` instead of tunnel URL
**Solution**: Ensure `DYNAMIC_TUNNEL_URL` is set in `.env` and restart game-server

#### 2. Services Not Starting on Pi
**Problem**: Docker build timeout on Pi hardware
**Solution**: Build takes 2-3 minutes on Pi. Use deployment scripts which show progress

#### 3. Tunnel URL Not Found
**Problem**: Can't get Cloudflare tunnel URL
**Solution**: 
```bash
ssh pi@192.168.1.222
sudo systemctl status cloudflare-tunnel
sudo systemctl restart cloudflare-tunnel
cat ~/cloudflare-tunnel-url.txt
```

#### 4. iOS App Can't Connect
**Problem**: App shows connection errors
**Solution**: 
- Check if using correct environment: `./build_multi_sim.sh [local|staging|aws]`
- Verify services are running: `docker-compose ps`
- Check server logs: `docker-compose logs -f game-server`

### Debug Commands

```bash
# Check service health
curl http://localhost:3000/api/status

# View Docker logs
docker-compose -f docker-compose.services.yml logs -f

# SSH to Pi
ssh pi@192.168.1.222

# Check tunnel URL on Pi
cat ~/cloudflare-tunnel-url.txt

# Force recreate containers
docker-compose -f docker-compose.services.yml up -d --force-recreate

# Clean Docker system
docker system prune -a
```

## Deployment Checklist

### Before Deployment
- [ ] All changes committed to git
- [ ] Tests passing locally
- [ ] Environment variables updated if needed
- [ ] Docker services running locally

### During Deployment
- [ ] Services stop cleanly
- [ ] New code synced successfully
- [ ] Tunnel URL obtained (staging only)
- [ ] Services start without errors
- [ ] iOS apps build successfully

### After Deployment
- [ ] API health checks pass
- [ ] Contribution system working
- [ ] WebSocket connections stable
- [ ] iOS apps connect successfully
- [ ] Test phrase creation and retrieval

## Security Notes

- **Never commit** `.env` files with production credentials
- **Always use** `SECURITY_RELAXED=false` in production
- **Rotate** API keys regularly
- **Monitor** rate limiting and security logs
- **Update** dependencies regularly

## Support

For issues or questions:
1. Check logs: `docker-compose logs -f [service-name]`
2. Review this guide's troubleshooting section
3. Check CLAUDE.md for development guidelines
4. Review git history for working implementations

---

*Last Updated: August 2025*
*Architecture: 3-service consolidated model*
*Contribution System: Integrated into Game Server*