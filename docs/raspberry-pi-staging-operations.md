# Raspberry Pi Staging Server - Operations Guide

## 🎯 Overview
Your Raspberry Pi runs a complete staging environment with automatic startup, global access via Cloudflare tunnel, and bulletproof reliability.

**Services Running:**
- **Nginx Reverse Proxy** (port 80) - Single entry point for all services
- **Game Server** (port 3000) - Main multiplayer API + WebSocket
- **Web Dashboard** (port 3001) - Monitoring interface  
- **Link Generator** (port 3002) - Contribution system
- **Admin Service** (port 3003) - Content management
- **PostgreSQL** (port 5432) - Database
- **Cloudflare Tunnel** - Public access (URL changes on restart)

---

## 🔄 Daily Operations Routine

### Check Server Status
```bash
# SSH into Pi
ssh pi@192.168.1.222

# Check all services with nginx reverse proxy
docker-compose -f docker-compose.nginx.yml ps

# Get current Cloudflare tunnel URL
docker-compose -f docker-compose.nginx.yml logs cloudflared | grep "trycloudflare.com" | tail -1

# Test service health through reverse proxy
curl http://localhost/api/status
```

### Monitor Health
```bash
# Check server health via public URL
curl -s https://YOUR_NGROK_URL/api/status | jq .

# View dashboard
open http://192.168.1.222:3001/monitoring/

# Check logs
docker logs anagram-game-server --tail 50
```

---

## 🚨 REBOOT RECOVERY PROCEDURE

**When Pi reboots, ngrok gets a new URL. Follow these steps:**

### Step 1: Get New ngrok URL
```bash
# SSH into Pi  
ssh pi@192.168.1.222

# Verify services started
sudo systemctl status ngrok anagram-game
docker ps

# Get new ngrok URL
curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
# Example output: https://abc123def456.ngrok-free.app
```

### Step 2: Update iOS App Configuration
```bash
# On your Mac, edit the network configuration
vim Models/Network/NetworkConfiguration.swift

# Update line 62 with new ngrok URL:
let developmentConfig = EnvironmentConfig(host: "NEW_NGROK_URL_HERE")
# Example: let developmentConfig = EnvironmentConfig(host: "abc123def456.ngrok-free.app")
```

### Step 3: Rebuild and Test Apps
```bash
# Build with new configuration
./build_and_test.sh local

# Verify connection in logs
./Scripts/tail-logs.sh | grep -E "(CONFIG|ngrok|https://)"
```

### Step 4: Test Connection
```bash
# Test new URL works
curl -s https://NEW_NGROK_URL/api/status | jq .

# Should show: "status": "healthy"
```

---

## 🔧 Quick Commands Reference

### Service Management
```bash
# Restart ngrok (gets new URL)
sudo systemctl restart ngrok

# Restart all game services  
sudo systemctl restart anagram-game

# Check ngrok logs
sudo journalctl -u ngrok.service -f

# Check game service logs
sudo journalctl -u anagram-game.service -f
```

### Get Current Status
```bash
# Current ngrok URL
curl -s http://192.168.1.222:4040/api/tunnels | jq -r '.tunnels[0].public_url'

# Service health
curl -s https://YOUR_NGROK_URL/api/status | jq .

# Container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### iOS App Updates
```bash
# Update app with new URL
vim Models/Network/NetworkConfiguration.swift
# Change line 62: let developmentConfig = EnvironmentConfig(host: "NEW_URL")

# Rebuild apps
./build_and_test.sh local

# Check app logs for connection
./Scripts/tail-logs.sh | grep -E "(CONFIG|LEVEL CONFIG)"
```

---

## 🐛 Troubleshooting

### ngrok Not Starting
```bash
# Check if ngrok exists and is executable
ls -la ~/ngrok
chmod +x ~/ngrok

# Test manually
~/ngrok version
~/ngrok http 3000

# Check service logs
sudo journalctl -u ngrok.service -n 20
```

### Docker Services Not Starting
```bash
# Check Docker daemon
sudo systemctl status docker

# Check compose file exists
ls -la ~/anagram-game/docker-compose.services.yml

# Manual start
cd ~/anagram-game
docker-compose -f docker-compose.services.yml up -d

# Check logs
docker-compose -f docker-compose.services.yml logs -f
```

### Network Issues
```bash
# Check network interfaces
ip route

# Test internet connectivity
ping google.com

# Check if ports are open
netstat -tlnp | grep -E ":300[0-3]"
```

### iOS App Not Connecting
```bash
# Verify app configuration
grep -n "ngrok-free.app" Models/Network/NetworkConfiguration.swift

# Check what URL app is trying to use
./Scripts/tail-logs.sh | grep -E "(CONFIG|Using.*server)"

# Test URL manually
curl -s https://YOUR_NGROK_URL/api/status
```

---

## 📋 Maintenance Checklist

### Weekly
- [ ] Check disk space: `df -h`
- [ ] Check memory usage: `free -h`  
- [ ] Update packages: `sudo apt update && sudo apt upgrade`
- [ ] Check logs for errors: `sudo journalctl --since "1 week ago" | grep -i error`

### Monthly  
- [ ] Restart Pi for fresh start: `sudo reboot`
- [ ] Update ngrok URL in iOS app after reboot
- [ ] Test full deployment cycle
- [ ] Backup important data: `docker exec anagram-db pg_dump -U postgres anagram_game > backup.sql`

---

## 🔗 Quick Reference URLs

**Local Access (from same network):**
- Dashboard: http://192.168.1.222:3001/monitoring/
- ngrok Admin: http://192.168.1.222:4040
- Direct API: http://192.168.1.222:3000/api/status

**External Access (worldwide):**
- Public API: https://YOUR_NGROK_URL/api/status
- Get current URL: `curl -s http://192.168.1.222:4040/api/tunnels | jq -r '.tunnels[0].public_url'`

---

## 🚀 Deployment Updates

### Deploy Code Changes
```bash
# From your Mac
./scripts/deploy-to-pi.sh 192.168.1.222

# This will:
# - Sync latest code to Pi
# - Rebuild Docker containers  
# - Restart services
# - Keep same ngrok URL (no iOS app update needed)
```

### Emergency Recovery
```bash
# If everything breaks, nuclear option:
ssh pi@192.168.1.222
cd ~/anagram-game
docker-compose -f docker-compose.services.yml down
docker system prune -f
sudo systemctl restart ngrok anagram-game
```

---

## 💡 Pro Tips

1. **Bookmark the ngrok admin**: http://192.168.1.222:4040 to quickly check current URL
2. **Use aliases** for common commands:
   ```bash
   alias piurl='curl -s http://192.168.1.222:4040/api/tunnels | jq -r ".tunnels[0].public_url"'
   alias pistatus='ssh pi@192.168.1.222 "sudo systemctl status ngrok anagram-game && docker ps"'
   ```
3. **Monitor from phone**: The dashboard works great on mobile at http://192.168.1.222:3001/monitoring/
4. **Keep a log** of ngrok URLs for reference (they change after each reboot)

---

**Remember: After any Pi reboot, you must update the iOS app with the new ngrok URL!**