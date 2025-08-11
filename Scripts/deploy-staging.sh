#!/bin/bash

# Unified Pi Staging Deployment Script
# Complete staging deployment with one command

set -e

# Configuration
PI_IP="192.168.1.222"
PI_USER="pi"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Deploying to Pi Staging Server${NC}"
echo "====================================="

# 1. Sync code
echo -e "\n${YELLOW}📦 Syncing code to Pi...${NC}"
rsync -avz --exclude 'node_modules' --exclude '.git' --exclude 'logs' \
  ./services/ ${PI_USER}@${PI_IP}:~/anagram-game/services/ > /dev/null 2>&1
rsync -avz ./docker-compose.services.yml ${PI_USER}@${PI_IP}:~/anagram-game/ > /dev/null 2>&1
echo -e "${GREEN}✅ Code synced${NC}"

# 2. Restart services on Pi with tunnel URL
echo -e "\n${YELLOW}🔄 Restarting services on Pi...${NC}"
ssh ${PI_USER}@${PI_IP} << 'ENDSSH'
cd ~/anagram-game
echo "Stopping old services..."
docker-compose -f docker-compose.services.yml down 2>/dev/null || true

echo "Checking existing tunnel..."
TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt 2>/dev/null || echo "")

if [ -n "$TUNNEL_URL" ]; then
    echo "Testing existing tunnel: $TUNNEL_URL"
    if curl -s --max-time 10 "$TUNNEL_URL/api/status" > /dev/null 2>&1; then
        echo "✅ Existing tunnel is working, reusing: $TUNNEL_URL"
    else
        echo "❌ Existing tunnel not working, generating new one..."
        sudo systemctl restart cloudflare-tunnel 2>/dev/null || true
        sleep 10
        TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt 2>/dev/null || echo "")
        echo "New tunnel URL: $TUNNEL_URL"
    fi
else
    echo "No existing tunnel found, starting fresh..."
    sudo systemctl restart cloudflare-tunnel 2>/dev/null || true
    sleep 10
    TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt 2>/dev/null || echo "")
    echo "New tunnel URL: $TUNNEL_URL"
fi

if [ -z "$TUNNEL_URL" ]; then
    echo "ERROR: Could not get tunnel URL"
    exit 1
fi

# Update .env file with tunnel URL
grep -v "DYNAMIC_TUNNEL_URL" .env > .env.tmp 2>/dev/null || true
echo "DYNAMIC_TUNNEL_URL=$TUNNEL_URL" >> .env.tmp
mv .env.tmp .env

echo "Starting services (this takes 2-3 minutes on Pi hardware)..."
docker-compose -f docker-compose.services.yml up -d --build --remove-orphans
ENDSSH

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to restart services on Pi${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Services restarted${NC}"

# 3. Wait for initialization
echo -e "\n${YELLOW}⏳ Waiting 30 seconds for services to initialize...${NC}"
for i in {30..1}; do
    echo -ne "\r   ${i} seconds remaining..."
    sleep 1
done
echo -e "\r   ${GREEN}Ready!${NC}                        "

# 4. Get tunnel URL for iOS build
echo -e "\n${YELLOW}🌐 Getting Cloudflare tunnel URL...${NC}"
TUNNEL_URL=$(ssh ${PI_USER}@${PI_IP} "cat ~/cloudflare-tunnel-url.txt 2>/dev/null" || echo "")

if [ -z "$TUNNEL_URL" ]; then
    echo -e "${RED}❌ Could not get tunnel URL${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Tunnel URL: ${TUNNEL_URL}${NC}"

# 5. Test health
echo -e "\n${YELLOW}🔍 Testing server health...${NC}"
if curl -s --connect-timeout 10 "${TUNNEL_URL}/api/status" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Server is healthy${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed but continuing...${NC}"
fi

# 6. Build and deploy iOS apps
echo -e "\n${YELLOW}📱 Building iOS apps for staging...${NC}"
export PI_TUNNEL_URL="$TUNNEL_URL"
./build_multi_sim.sh staging

echo -e "\n${GREEN}🎉 Staging Deployment Complete!${NC}"
echo "================================"
echo -e "${BLUE}Summary:${NC}"
echo "  • Services running on Pi: ${PI_IP}"
echo "  • Tunnel URL: ${TUNNEL_URL}"
echo "  • iOS apps deployed to iPhone 15 simulators"
echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "  1. Test the apps on both simulators"
echo "  2. Verify contribution links use tunnel URL"
echo "  3. Check multiplayer functionality"
echo ""
echo -e "${BLUE}💡 Troubleshooting:${NC}"
echo "  • View logs: ssh ${PI_USER}@${PI_IP} 'cd ~/anagram-game && docker-compose logs -f'"
echo "  • Restart tunnel: ssh ${PI_USER}@${PI_IP} 'sudo systemctl restart cloudflare-tunnel'"