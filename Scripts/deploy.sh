#!/bin/bash

# 🚀 Unified Deployment Script for Wordshelf Staging
# Usage: ./scripts/deploy.sh [options] [files...]
# 
# Options:
#   --full          Full rebuild with Docker cache clearing (slow)
#   --check         Only verify deployment health
#   --help          Show this help
#
# Examples:
#   ./scripts/deploy.sh                                    # Quick deploy all changes (10-15s)
#   ./scripts/deploy.sh server/file.js                     # Deploy specific file (10s)
#   ./scripts/deploy.sh --full                             # Full rebuild (2-5min)
#   ./scripts/deploy.sh --check                            # Verify deployment

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
    echo "Options:"
    echo "  --full          Full Docker rebuild (for major changes)"
    echo "  --check         Health check only"
    echo "  --help          Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  PI_HOST         Pi IP address (default: 192.168.1.222)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Quick deploy (most common)"
    echo "  $0 server/contribution-link-generator.js  # Deploy single file"
    echo "  PI_HOST=192.168.1.100 $0             # Deploy to different Pi"
}

check_deployment() {
    echo -e "${BLUE}🔍 DEPLOYMENT HEALTH CHECK${NC}"
    
    # Check Pi connectivity
    if ! ping -c 1 -W 2000 $PI_HOST > /dev/null 2>&1; then
        echo -e "${RED}❌ Cannot reach Pi at $PI_HOST${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Pi connectivity OK${NC}"
    
    # Check containers
    CONTAINERS=$(ssh -q $PI_USER@$PI_HOST "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || echo "")
    if echo "$CONTAINERS" | grep -q "anagram-server"; then
        echo -e "${GREEN}✅ Containers running${NC}"
    else
        echo -e "${RED}❌ Containers not running${NC}"
        echo "   Run: ./scripts/deploy.sh --full"
        exit 1
    fi
    
    # Check service health
    if curl -s --connect-timeout 5 http://$PI_HOST:3000/api/status > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Service responding on Pi IP${NC}"
    else
        echo -e "${RED}❌ Service not responding on Pi IP${NC}"
    fi
    
    # Check Cloudflare tunnel
    TUNNEL_STATUS=$(curl -s --connect-timeout 5 https://bras-voluntary-survivor-presidential.trycloudflare.com/api/status || echo "unreachable")
    if echo "$TUNNEL_STATUS" | grep -q "healthy"; then
        echo -e "${GREEN}✅ Cloudflare tunnel working${NC}"
    else
        echo -e "${YELLOW}⚠️  Cloudflare tunnel issue: $TUNNEL_STATUS${NC}"
    fi
    
    # Check contribution link fix
    if ssh -q $PI_USER@$PI_HOST "docker exec anagram-server grep -q 'x-forwarded-host' /project/server/contribution-link-generator.js 2>/dev/null"; then
        echo -e "${GREEN}✅ Cloudflare tunnel URL fix deployed${NC}"
    else
        echo -e "${YELLOW}⚠️  Contribution link fix may be missing${NC}"
    fi
    
    echo -e "${GREEN}🎉 Deployment health check complete${NC}"
}

quick_deploy() {
    echo -e "${YELLOW}⚡ QUICK DEPLOY - Target: 15 seconds${NC}"
    START_TIME=$(date +%s)
    
    # Delegate to the optimized quick-deploy script
    if [ -f "Scripts/quick-deploy.sh" ]; then
        Scripts/quick-deploy.sh "$@"
    else
        echo -e "${RED}❌ Quick deploy script not found${NC}"
        exit 1
    fi
}

full_deploy() {
    echo -e "${YELLOW}🏗️  FULL DEPLOY - Target: 2-5 minutes${NC}"
    echo -e "${YELLOW}   This rebuilds Docker containers completely${NC}"
    START_TIME=$(date +%s)
    
    # Delegate to the comprehensive deploy script
    if [ -f "Scripts/deploy-to-pi.sh" ]; then
        bash Scripts/deploy-to-pi.sh $PI_HOST
    else
        echo -e "${RED}❌ Full deploy script not found${NC}"
        exit 1
    fi
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
            # File arguments - pass through to quick deploy
            break
            ;;
    esac
done

# Execute based on options
if [ "$CHECK_ONLY" = true ]; then
    check_deployment
elif [ "$FULL_DEPLOY" = true ]; then
    full_deploy
else
    quick_deploy "$@"
fi