#!/bin/bash

# FAST deployment script for quick iterations (< 1 minute)
# Usage: ./Scripts/quick-deploy.sh [file1] [file2] ...
# Examples:
#   ./Scripts/quick-deploy.sh                                    # Deploy all server changes
#   ./Scripts/quick-deploy.sh server/contribution-link-generator.js  # Deploy specific file

set -e

PI_HOST=${PI_HOST:-192.168.1.222}
PI_USER="pi"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}⚡ QUICK DEPLOY - Target: 30 seconds${NC}"
START_TIME=$(date +%s)

# Quick connectivity check (2 seconds max)
if ! timeout 2 ping -c 1 $PI_HOST > /dev/null 2>&1; then
    echo -e "${RED}❌ Cannot reach Pi at $PI_HOST${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Pi${NC}"

# If specific files provided, only sync those
if [ $# -gt 0 ]; then
    echo -e "${YELLOW}📦 Syncing specific files...${NC}"
    for file in "$@"; do
        if [ -f "$file" ]; then
            echo "   • $file"
            scp -q "$file" $PI_USER@$PI_HOST:/home/pi/anagram-game/"$file"
        else
            echo -e "${RED}   ⚠️  File not found: $file${NC}"
        fi
    done
else
    echo -e "${YELLOW}📦 Syncing server directory...${NC}"
    # Only sync server and services directories (the most commonly changed)
    rsync -azq --delete \
        --exclude 'node_modules' \
        --exclude '*.log' \
        server/ $PI_USER@$PI_HOST:/home/pi/anagram-game/server/
    
    rsync -azq --delete \
        --exclude 'node_modules' \
        services/ $PI_USER@$PI_HOST:/home/pi/anagram-game/services/ 2>/dev/null || true
fi

echo -e "${YELLOW}🐳 Hot-patching container...${NC}"

# Direct copy to container and restart (no rebuild)
ssh -q $PI_USER@$PI_HOST << 'EOF'
    cd ~/anagram-game
    
    # Copy directly into running container
    docker cp server/ anagram-server:/project/ 2>/dev/null || {
        echo "   ⚠️  Container not running, starting..."
        docker-compose up -d server
        sleep 5
        docker cp server/ anagram-server:/project/
    }
    
    docker cp services/ anagram-server:/project/ 2>/dev/null || true
    
    # Quick restart (faster than rebuild)
    docker restart anagram-server > /dev/null
EOF

echo -e "${YELLOW}⏳ Waiting for service (15 seconds max)...${NC}"

# Quick health check
READY=false
for i in {1..15}; do
    if curl -s --connect-timeout 1 http://$PI_HOST:3000/api/status > /dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 1
done

if [ "$READY" = true ]; then
    echo -e "${GREEN}✅ Service is ready!${NC}"
    
    # Quick verification for common issues
    if ssh -q $PI_USER@$PI_HOST "docker exec anagram-server grep -q 'x-forwarded-host' /project/server/contribution-link-generator.js 2>/dev/null"; then
        echo -e "${GREEN}✅ Cloudflare tunnel fix verified${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Service may still be starting...${NC}"
fi

TOTAL_TIME=$(($(date +%s) - START_TIME))
echo -e "${GREEN}🚀 Deployment complete in ${TOTAL_TIME} seconds!${NC}"

if [ $TOTAL_TIME -gt 60 ]; then
    echo -e "${YELLOW}💡 Tip: Deployment took > 1 minute. Consider:${NC}"
    echo "   • Using specific file arguments: ./Scripts/quick-deploy.sh server/file.js"
    echo "   • Checking Pi performance: ssh $PI_USER@$PI_HOST 'docker stats --no-stream'"
else
    echo -e "${GREEN}⚡ Target time achieved!${NC}"
fi

# Quick test of Cloudflare URL
echo -e "\n${YELLOW}🌐 Testing via Cloudflare tunnel...${NC}"
TUNNEL_STATUS=$(curl -s https://bras-voluntary-survivor-presidential.trycloudflare.com/api/status | grep -o '"status":"[^"]*"' || echo "unreachable")
echo -e "   Tunnel status: $TUNNEL_STATUS"