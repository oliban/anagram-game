#!/bin/bash

# Enhanced build script with server health checking
# Usage: ./build_and_test.sh [local|aws] [--clean] [--physical]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
ENV_MODE="local"
CLEAN_FLAG=""
PHYSICAL_FLAG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    aws)
      ENV_MODE="aws"
      shift
      ;;
    local)
      ENV_MODE="local"
      shift
      ;;
    --clean)
      CLEAN_FLAG="--clean"
      shift
      ;;
    --physical|--device)
      PHYSICAL_FLAG="--physical"
      shift
      ;;
    *)
      echo "Usage: $0 [local|aws] [--clean] [--physical]"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}🚀 Starting build and test workflow for ${ENV_MODE} environment${NC}"

# Function to check server health
check_server_health() {
    local service_name=$1
    local name=$2
    local timeout=${3:-10}
    local port=${4:-3000}
    
    # Get the local network IP address
    LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "192.168.1.133")
    
    echo -e "${YELLOW}🔍 Checking ${name} server health (Docker service: ${service_name}) at ${LOCAL_IP}:${port}${NC}"
    
    if curl -s --connect-timeout $timeout "http://${LOCAL_IP}:${port}/api/status" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ ${name} server is healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ ${name} server is not responding${NC}"
        return 1
    fi
}

# Function to show server startup instructions
show_server_startup_guide() {
    local env=$1
    
    if [ "$env" = "local" ]; then
        echo -e "${YELLOW}📋 To start local development servers:${NC}"
        echo -e "   docker-compose -f docker-compose.services.yml up -d"
        echo -e "   ${BLUE}Wait ~30 seconds for services to initialize${NC}"
    else
        echo -e "${YELLOW}📋 To start AWS production servers:${NC}"
        echo -e "   See 'AWS Production Server Management' section in CLAUDE.md"
        echo -e "   ${BLUE}Typical startup time: 2-5 minutes${NC}"
    fi
}

# Pre-build server health checks
if [ "$ENV_MODE" = "local" ]; then
    echo -e "${BLUE}🔍 Checking local development servers...${NC}"
    
    if ! check_server_health "game-server" "Local Game Server" 3; then
        echo -e "${RED}❌ Local servers are not running!${NC}"
        echo ""
        show_server_startup_guide "local"
        echo ""
        read -p "Start servers now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}🚀 Starting local services...${NC}"
            docker-compose -f docker-compose.services.yml up -d
            
            echo -e "${YELLOW}⏳ Waiting for services to initialize...${NC}"
            sleep 15
            
            # Re-check health
            if check_server_health "game-server" "Local Game Server" 5; then
                echo -e "${GREEN}✅ Local servers are now ready!${NC}"
            else
                echo -e "${RED}❌ Local servers failed to start properly${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ Cannot proceed without servers. Exiting.${NC}"
            exit 1
        fi
    fi
    
else
    echo -e "${BLUE}🔍 Checking AWS production servers...${NC}"
    
    AWS_SERVER_URL="http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com"
    if ! check_server_health "$AWS_SERVER_URL" "AWS Production Server" 10; then
        echo -e "${RED}❌ AWS production servers are not running!${NC}"
        echo ""
        show_server_startup_guide "aws"
        echo ""
        echo -e "${YELLOW}⚠️  AWS servers must be started manually via AWS Console/CLI${NC}"
        echo -e "${BLUE}💡 Check CLAUDE.md for detailed AWS startup instructions${NC}"
        echo ""
        read -p "Continue anyway to build app for when servers come online? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ Build cancelled. Start AWS servers first.${NC}"
            exit 1
        fi
    fi
fi

echo ""
echo -e "${GREEN}✅ Server health checks passed!${NC}"
echo ""

# Build the app
echo -e "${BLUE}🔨 Building iOS app for ${ENV_MODE} environment...${NC}"
./build_multi_sim.sh $ENV_MODE $CLEAN_FLAG $PHYSICAL_FLAG

# Post-build verification
echo ""
echo -e "${BLUE}🔍 Post-build verification...${NC}"

if [ "$ENV_MODE" = "local" ]; then
    # Check local server logs for connections
    echo -e "${YELLOW}📋 Recent local server activity:${NC}"
    docker-compose -f docker-compose.services.yml logs --tail=5 game-server
else
    # For AWS, remind about monitoring
    echo -e "${YELLOW}📋 Monitor AWS server logs via:${NC}"
    echo -e "   AWS Console → ECS → anagram-game-cluster → Service logs"
    echo -e "   Or use AWS CLI: aws logs tail /ecs/anagram-game-server --follow"
fi

echo ""
echo -e "${GREEN}🎉 Build and test workflow complete!${NC}"
echo -e "${BLUE}💡 Next steps:${NC}"
if [ "$ENV_MODE" = "local" ]; then
    echo -e "   1. Test app on iPhone 15 simulators"
    echo -e "   2. Register different players on each device"
    echo -e "   3. Monitor server logs: docker-compose -f docker-compose.services.yml logs -f game-server"
else
    echo -e "   1. Test app on iPhone SE simulator"
    echo -e "   2. Register a player and test functionality"
    echo -e "   3. Monitor AWS CloudWatch logs for connection issues"
fi