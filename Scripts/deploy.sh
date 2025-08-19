#!/bin/bash

# 🚀 Unified Deployment Script for Wordshelf Staging
# Usage: ./scripts/deploy.sh [options] [files...]

set -e

PI_HOST=${PI_HOST:-192.168.1.222}
PI_USER="pi"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    echo "🚀 Wordshelf Deployment Script"
    echo ""
    echo "Usage: $0 [options] [files...]"
    echo ""
    echo "Quick Commands:"
    echo "  $0                           Deploy all server changes (10-15 seconds)"
    echo "  $0 server/file.js            Deploy specific file (10 seconds)"
    echo "  $0 --full                    Full rebuild with Docker cache clear (2-5 minutes)"
    echo "  $0 --check                   Verify deployment health only"
    echo ""
    echo "Environment Variables:"
    echo "  PI_HOST         Pi IP address (default: 192.168.1.222)"
}

check_deployment() {
    echo -e "${BLUE}🔍 DEPLOYMENT HEALTH CHECK${NC}"
    
    if ! ping -c 1 -W 2000 $PI_HOST > /dev/null 2>&1; then
        echo -e "${RED}❌ Cannot reach Pi at $PI_HOST${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Pi connectivity OK${NC}"
    
    CONTAINERS=$(ssh -o ConnectTimeout=5 -q $PI_USER@$PI_HOST "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || echo "")
    if echo "$CONTAINERS" | grep -q "anagram-server"; then
        echo -e "${GREEN}✅ Containers running${NC}"
    else
        echo -e "${RED}❌ Containers not running${NC}"
        exit 1
    fi
    
    if curl -s --connect-timeout 5 http://$PI_HOST:3000/api/status > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Service responding${NC}"
    else
        echo -e "${RED}❌ Service not responding${NC}"
    fi
    
    TUNNEL_STATUS=$(curl -s --connect-timeout 5 https://bras-voluntary-survivor-presidential.trycloudflare.com/api/status || echo "unreachable")
    if echo "$TUNNEL_STATUS" | grep -q "healthy"; then
        echo -e "${GREEN}✅ Cloudflare tunnel working${NC}"
    else
        echo -e "${YELLOW}⚠️  Cloudflare tunnel issue${NC}"
    fi
    
    if ssh -o ConnectTimeout=3 -q $PI_USER@$PI_HOST "docker exec anagram-server grep -q 'x-forwarded-host' /project/server/contribution-link-generator.js 2>/dev/null"; then
        echo -e "${GREEN}✅ Cloudflare URL fix deployed${NC}"
    else
        echo -e "${YELLOW}⚠️  Contribution link fix missing${NC}"
    fi
    
    echo -e "${GREEN}🎉 Deployment health check complete${NC}"
}

quick_deploy() {
    echo -e "${YELLOW}⚡ QUICK DEPLOY - Target: 15 seconds${NC}"
    START_TIME=$(date +%s)
    
    if ! ping -c 1 -W 2000 $PI_HOST > /dev/null 2>&1; then
        echo -e "${RED}❌ Cannot reach Pi at $PI_HOST${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Connected to Pi${NC}"
    
    # Sync files
    if [ $# -gt 0 ]; then
        echo -e "${YELLOW}📦 Syncing specific files...${NC}"
        for file in "$@"; do
            if [ -f "$file" ]; then
                echo "   • $file"
                scp -o ConnectTimeout=5 -q "$file" $PI_USER@$PI_HOST:/home/pi/anagram-game/"$file"
            else
                echo -e "${RED}   ⚠️  File not found: $file${NC}"
            fi
        done
    else
        echo -e "${YELLOW}📦 Syncing server directory...${NC}"
        rsync -azq --delete --exclude 'node_modules' --exclude '*.log' \
            server/ $PI_USER@$PI_HOST:/home/pi/anagram-game/server/
        rsync -azq --delete --exclude 'node_modules' \
            services/ $PI_USER@$PI_HOST:/home/pi/anagram-game/services/ 2>/dev/null || true
    fi
    
    # Hot-patch container
    echo -e "${YELLOW}🐳 Hot-patching container...${NC}"
    ssh -o ConnectTimeout=5 -q $PI_USER@$PI_HOST << 'EOF'
        cd ~/anagram-game
        docker cp server/ anagram-server:/project/ 2>/dev/null || {
            echo "Container not running, starting..."
            docker-compose up -d server
            sleep 5
            docker cp server/ anagram-server:/project/
        }
        docker cp services/ anagram-server:/project/ 2>/dev/null || true
        docker restart anagram-server > /dev/null
EOF
    
    # Health check
    echo -e "${YELLOW}⏳ Waiting for service...${NC}"
    for i in {1..10}; do
        if curl -s --connect-timeout 1 --max-time 2 http://$PI_HOST:3000/api/status > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Service ready!${NC}"
            break
        fi
        sleep 1
    done
    
    TOTAL_TIME=$(($(date +%s) - START_TIME))
    echo -e "${GREEN}🚀 Deployment complete in ${TOTAL_TIME} seconds!${NC}"
    
    # Quick tunnel test
    TUNNEL_STATUS=$(curl -s --connect-timeout 3 https://bras-voluntary-survivor-presidential.trycloudflare.com/api/status | grep -o '"status":"[^"]*"' || echo "unreachable")
    echo -e "${YELLOW}🌐 Tunnel status: $TUNNEL_STATUS${NC}"
}

full_deploy() {
    echo -e "${YELLOW}🏗️  FULL DEPLOY - Rebuilding containers${NC}"
    START_TIME=$(date +%s)
    
    if ! ping -c 1 -W 2000 $PI_HOST > /dev/null 2>&1; then
        echo -e "${RED}❌ Cannot reach Pi at $PI_HOST${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}📦 Syncing all files...${NC}"
    rsync -azq --delete \
        --exclude 'node_modules' --exclude '.git' --exclude 'build' \
        --exclude '*.xcworkspace' --exclude '*.xcodeproj' --exclude 'Pods' \
        --exclude '.env*' --exclude 'postgres_data' --exclude '*.log' \
        --exclude 'Models' --exclude 'Views' --exclude 'Extensions' \
        ./ $PI_USER@$PI_HOST:/home/pi/anagram-game/
    
    echo -e "${YELLOW}🔨 Rebuilding containers...${NC}"
    ssh -o ConnectTimeout=10 -q $PI_USER@$PI_HOST << 'EOF'
        cd ~/anagram-game
        docker-compose down || true
        docker container prune -f || true
        docker image prune -f || true
        docker-compose build --no-cache server
        docker-compose up -d
EOF
    
    echo -e "${YELLOW}⏳ Waiting for service startup...${NC}"
    sleep 15
    for i in {1..30}; do
        if curl -s --connect-timeout 2 http://$PI_HOST:3000/api/status > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Service ready!${NC}"
            break
        fi
        sleep 2
    done
    
    TOTAL_TIME=$(($(date +%s) - START_TIME))
    echo -e "${GREEN}🚀 Full deployment complete in ${TOTAL_TIME} seconds!${NC}"
}

# Parse arguments
FULL_DEPLOY=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_DEPLOY=true
            shift
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Execute
if [ "$CHECK_ONLY" = true ]; then
    check_deployment
elif [ "$FULL_DEPLOY" = true ]; then
    full_deploy
else
    quick_deploy "$@"
fi