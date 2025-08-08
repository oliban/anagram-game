#!/bin/bash

# Build and launch Anagram Game with multi-device configuration
# 
# USAGE:
#   ./build_multi_sim.sh [local|staging|aws] [--clean] [--physical]
#
# ARGUMENTS:
#   local   - Deploy to iPhone 15 devices with local backend (default)
#   staging - Deploy to iPhone 15 devices with Pi staging server  
#   aws     - Deploy to iPhone SE with AWS backend
#   --clean - Force clean build (removes cache, slower but reliable)
#   --physical - Deploy to physical device instead of simulator
#
# EXAMPLES:
#   ./build_multi_sim.sh                    # Local development (iPhone 15s)
#   ./build_multi_sim.sh local              # Local development (iPhone 15s)
#   ./build_multi_sim.sh staging            # Pi staging server (iPhone 15s)
#   ./build_multi_sim.sh aws                # AWS production (iPhone SE)
#   ./build_multi_sim.sh staging --clean    # Pi staging with clean build
#
# DEVICE CONFIGURATION:
# - LOCAL MODE: iPhone 15 & iPhone 15 Pro for local development (fixed IP)
# - STAGING MODE: iPhone 15 & iPhone 15 Pro for Pi staging server (tunnel URL changes on reboot)
# - AWS MODE: iPhone SE for production testing (stable URL)

set -e

# Parse command line arguments
ENV_MODE="LOCAL"  # Default
FORCE_CLEAN="0"
PHYSICAL_FLAG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    aws)
      ENV_MODE="AWS"
      shift
      ;;
    local)
      ENV_MODE="LOCAL" 
      shift
      ;;
    staging)
      ENV_MODE="STAGING"
      shift
      ;;
    --clean)
      FORCE_CLEAN="1"
      shift
      ;;
    --physical|--device)
      PHYSICAL_FLAG="--physical"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [local|staging|aws] [--clean] [--physical]"
      exit 1
      ;;
  esac
done

# Legacy environment variable support (for backwards compatibility)
if [ "$LOCAL" = "1" ]; then
    ENV_MODE="LOCAL"
fi
if [ "$FORCE_CLEAN" != "1" ] && [ "${FORCE_CLEAN_ENV}" = "1" ]; then
    FORCE_CLEAN="1"
fi

# Configure simulators based on environment
if [ "$ENV_MODE" = "LOCAL" ]; then
    ENV_DESC="local server (parallel development)"
    # Local development uses iPhone 15 devices (reserved for local development)
    SIM1_UUID="AF307F12-A657-4D6A-8123-240CBBEC5B31"  # iPhone 15
    SIM2_UUID="86355D8A-560E-465D-8FDC-3D037BCA482B"  # iPhone 15 Pro
    SIM1_NAME="iPhone 15"
    SIM2_NAME="iPhone 15 Pro"
    USE_MULTI_SIM=true
elif [ "$ENV_MODE" = "STAGING" ]; then
    ENV_DESC="Pi staging server (tunnel URL - changes on reboot)"
    # Staging uses same iPhone 15 devices as local development
    SIM1_UUID="AF307F12-A657-4D6A-8123-240CBBEC5B31"  # iPhone 15
    SIM2_UUID="86355D8A-560E-465D-8FDC-3D037BCA482B"  # iPhone 15 Pro
    SIM1_NAME="iPhone 15"
    SIM2_NAME="iPhone 15 Pro"
    USE_MULTI_SIM=true
else
    ENV_DESC="AWS cloud infrastructure"
    # AWS production uses iPhone SE (reserved for AWS production)
    SIM_UUID="046502C7-3D59-43F1-AA2D-EA2ADD0873B9"  # iPhone SE (3rd generation)
    SIM_NAME="iPhone SE (3rd generation)"
    USE_MULTI_SIM=false
fi

if [ "$USE_MULTI_SIM" = true ]; then
    if [ "$ENV_MODE" = "STAGING" ]; then
        echo "🚀 Building Wordshelf for Pi staging server (multi-simulator)..."
    else
        echo "🚀 Building Wordshelf for local development (multi-simulator)..."
    fi
    echo "📱 Devices: $SIM1_NAME + $SIM2_NAME"
else
    echo "🚀 Building Wordshelf for AWS production (single simulator)..."
    echo "📱 Device: $SIM_NAME"
fi
echo "🌐 Environment: $ENV_DESC"

# Configuration
APP_NAME="Wordshelf"
SCHEME="Wordshelf"
PROJECT_FILE="Wordshelf.xcodeproj"
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check server health
check_server_health() {
    local server_url=$1
    local server_name=$2
    local timeout=${3:-10}
    
    echo -e "${YELLOW}🔍 Checking ${server_name} server health at ${server_url}${NC}"
    
    if curl -s --connect-timeout $timeout "${server_url}/api/status" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ ${server_name} server is healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ ${server_name} server is not responding${NC}"
        return 1
    fi
}

# Function to get Pi tunnel URL
get_pi_tunnel_url() {
    local pi_ip="192.168.1.222"
    echo -e "${YELLOW}🔍 Getting current Pi tunnel URL...${NC}" >&2
    
    # Try to get Cloudflare tunnel URL from Pi
    if ssh pi@${pi_ip} "test -f ~/cloudflare-tunnel-url.txt" 2>/dev/null; then
        local tunnel_url=$(ssh pi@${pi_ip} "cat ~/cloudflare-tunnel-url.txt" 2>/dev/null)
        if [ -n "$tunnel_url" ]; then
            echo -e "${GREEN}✅ Found Cloudflare tunnel URL: ${tunnel_url}${NC}" >&2
            echo "$tunnel_url"
            return 0
        fi
    fi
    
    echo -e "${RED}❌ Could not get Cloudflare tunnel URL from Pi${NC}" >&2
    echo -e "${YELLOW}💡 Make sure cloudflare-tunnel service is running on Pi${NC}" >&2
    return 1
}

# Function to show server startup instructions
show_server_startup_guide() {
    local env=$1
    
    case $env in
        "LOCAL")
            echo -e "${YELLOW}📋 To start local development servers:${NC}"
            echo -e "   docker-compose -f docker-compose.services.yml up -d"
            echo -e "   ${BLUE}Wait ~30 seconds for services to initialize${NC}"
            ;;
        "STAGING")
            echo -e "${YELLOW}📋 To start Pi staging servers:${NC}"
            echo -e "   ssh pi@192.168.1.222"
            echo -e "   sudo systemctl start cloudflare-tunnel anagram-game"
            echo -e "   ${BLUE}Cloudflare tunnel URL persists across reboots!${NC}"
            ;;
        "AWS")
            echo -e "${YELLOW}📋 To start AWS production servers:${NC}"
            echo -e "   See 'AWS Production Server Management' section in CLAUDE.md"
            echo -e "   ${BLUE}Typical startup time: 2-5 minutes${NC}"
            ;;
    esac
}

echo -e "${BLUE}📱 Using simulator(s):${NC}"
if [ "$USE_MULTI_SIM" = true ]; then
    echo -e "  $SIM1_NAME ($SIM1_UUID)"
    echo -e "  $SIM2_NAME ($SIM2_UUID)"
else
    echo -e "  $SIM_NAME ($SIM_UUID)"
fi
echo ""

# Pre-build server health checks
echo -e "${BLUE}🔍 Checking server health before building...${NC}"

case $ENV_MODE in
    "LOCAL")
        # Get the local network IP address
        LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "192.168.1.133")
        
        if ! check_server_health "http://${LOCAL_IP}:3000" "Local Development" 3; then
            echo -e "${RED}❌ Local servers are not running!${NC}"
            echo ""
            show_server_startup_guide "LOCAL"
            echo ""
            read -p "Start servers now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}🚀 Starting local services...${NC}"
                docker-compose -f docker-compose.services.yml up -d
                
                echo -e "${YELLOW}⏳ Waiting for services to initialize...${NC}"
                sleep 15
                
                # Re-check health
                if check_server_health "http://${LOCAL_IP}:3000" "Local Development" 5; then
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
        ;;
    
    "STAGING")
        # For staging, just verify tunnel URL exists and proceed
        PI_TUNNEL_URL=$(get_pi_tunnel_url)
        if [ $? -eq 0 ] && [ -n "$PI_TUNNEL_URL" ]; then
            echo -e "${GREEN}✅ Pi staging tunnel detected: ${PI_TUNNEL_URL}${NC}"
            echo -e "${BLUE}💡 Note: Skipping health check for staging build speed${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not detect Pi tunnel URL, but proceeding with build${NC}"
            echo -e "${BLUE}💡 Make sure Pi staging server is running when testing${NC}"
        fi
        ;;
        
    "AWS")
        AWS_SERVER_URL="http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com"
        if ! check_server_health "$AWS_SERVER_URL" "AWS Production" 10; then
            echo -e "${RED}❌ AWS production servers are not running!${NC}"
            echo ""
            show_server_startup_guide "AWS"
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
        ;;
esac

echo ""
echo -e "${GREEN}✅ Server health checks completed!${NC}"
echo ""

# Function to boot simulator if not already running
boot_simulator() {
    local uuid=$1
    local name=$2
    
    echo -e "${YELLOW}🔄 Checking simulator: $name${NC}"
    
    # Check if simulator is already booted
    if xcrun simctl list devices | grep -q "$uuid.*Booted"; then
        echo -e "${GREEN}✅ $name is already booted${NC}"
    else
        echo -e "${YELLOW}🚀 Booting $name...${NC}"
        xcrun simctl boot "$uuid"
        
        # Wait for simulator to be ready
        echo -e "${YELLOW}⏳ Waiting for $name to be ready...${NC}"
        sleep 3
        
        # Open Simulator app
        open -a Simulator --args -CurrentDeviceUDID "$uuid"
        sleep 2
    fi
}

# Function to force clean cache (use when builds aren't reflecting code changes)
force_clean_cache() {
    echo -e "${YELLOW}🧹 Force cleaning build cache and simulator data...${NC}"
    
    # Remove derived data
    if [ -d "$DERIVED_DATA_PATH" ]; then
        echo -e "${YELLOW}  • Removing Xcode derived data...${NC}"
        rm -rf "$DERIVED_DATA_PATH"
    fi
    
    # Remove local build directory if it exists
    if [ -d "./build" ]; then
        echo -e "${YELLOW}  • Removing local build directory...${NC}"
        rm -rf "./build"
    fi
    
    echo -e "${GREEN}✅ Cache cleaned${NC}"
}

# Function to build and install app
build_and_install() {
    local uuid=$1
    local name=$2
    
    echo -e "${BLUE}🔨 Building for $name...${NC}"
    
    # Check if we should force clean (set FORCE_CLEAN=1 to enable)
    if [ "$FORCE_CLEAN" = "1" ]; then
        echo -e "${YELLOW}🧹 Force clean enabled - removing existing app first...${NC}"
        xcrun simctl uninstall "$uuid" com.fredrik.anagramgame 2>/dev/null || true
    fi
    
    # Build for simulator
    if [ "$FORCE_CLEAN" = "1" ]; then
        BUILD_ACTION="clean build"
        echo -e "${YELLOW}  • Using clean build (FORCE_CLEAN enabled)${NC}"
    else
        BUILD_ACTION="build"
        echo -e "${BLUE}  • Using incremental build (faster)${NC}"
    fi
    
    # Set environment variable for server selection
    case $ENV_MODE in
        "LOCAL")
            echo -e "${YELLOW}  • Setting USE_LOCAL_SERVER=local for parallel development${NC}"
            export USE_LOCAL_SERVER=local
            ;;
        "STAGING")
            echo -e "${BLUE}  • Setting USE_LOCAL_SERVER=staging for Pi staging server${NC}"
            export USE_LOCAL_SERVER=staging
            ;;
        "AWS")
            echo -e "${BLUE}  • Setting USE_LOCAL_SERVER=aws for AWS production${NC}"
            export USE_LOCAL_SERVER=aws
            ;;
    esac
    
    xcodebuild -project "$PROJECT_FILE" \
               -scheme "$SCHEME" \
               -destination "platform=iOS Simulator,id=$uuid" \
               -configuration Debug \
               $BUILD_ACTION \
               -quiet
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Build successful for $name${NC}"
        
        # Find the app bundle
        APP_PATH=$(find "$DERIVED_DATA_PATH" -name "*.app" -path "*/Build/Products/Debug-iphonesimulator/*" | grep -E "(Anagram.Game|Anagram-Game)" | head -1)
        
        if [ -n "$APP_PATH" ]; then
            echo -e "${BLUE}📦 Installing app on $name...${NC}"
            xcrun simctl install "$uuid" "$APP_PATH"
            
            echo -e "${BLUE}🚀 Launching app on $name...${NC}"
            xcrun simctl launch "$uuid" com.fredrik.anagramgame
            
            echo -e "${GREEN}✅ App launched on $name${NC}"
        else
            echo -e "${RED}❌ Could not find app bundle for $name${NC}"
            echo -e "${YELLOW}💡 Troubleshooting: Try running with FORCE_CLEAN=1 ./build_multi_sim.sh${NC}"
        fi
    else
        echo -e "${RED}❌ Build failed for $name${NC}"
        echo -e "${YELLOW}💡 Troubleshooting: Try running with FORCE_CLEAN=1 ./build_multi_sim.sh${NC}"
    fi
}

# Main execution
if [ "$USE_MULTI_SIM" = true ]; then
    echo -e "${BLUE}🎯 Starting multi-simulator build process for local development...${NC}"
else
    echo -e "${BLUE}🎯 Starting single simulator build process for AWS production...${NC}"
fi

# Check for force clean flag
if [ "$FORCE_CLEAN" = "1" ]; then
    force_clean_cache
fi

# Update NetworkConfiguration.swift with current environment
echo -e "${BLUE}⚙️ Configuring NetworkConfiguration.swift for ${ENV_MODE} environment...${NC}"

# Backup original file
cp Models/Network/NetworkConfiguration.swift Models/Network/NetworkConfiguration.swift.backup

# Update the static environment configuration using Python script
if [ "$ENV_MODE" = "STAGING" ]; then
    # For staging, update both environment and tunnel URL
    if [ -n "$PI_TUNNEL_URL" ]; then
        python3 update_network_config.py staging "$PI_TUNNEL_URL"
    else
        python3 update_network_config.py staging
    fi
elif [ "$ENV_MODE" = "AWS" ]; then
    python3 update_network_config.py aws
else
    # Local mode - ensure it's set to local (it's already the default)
    python3 update_network_config.py local
fi

if [ "$USE_MULTI_SIM" = true ]; then
    # Multi-simulator setup for local development or staging
    if [ "$ENV_MODE" = "STAGING" ]; then
        echo -e "${BLUE}🔄 Booting Pi staging simulators...${NC}"
    else
        echo -e "${BLUE}🔄 Booting local development simulators...${NC}"
    fi
    boot_simulator "$SIM1_UUID" "$SIM1_NAME" &
    boot_simulator "$SIM2_UUID" "$SIM2_NAME" &
    wait
    
    echo -e "${BLUE}⏳ Waiting for simulators to stabilize...${NC}"
    sleep 5
    
    echo -e "${BLUE}🔨 Building and installing on both simulators...${NC}"
    build_and_install "$SIM1_UUID" "$SIM1_NAME"
    build_and_install "$SIM2_UUID" "$SIM2_NAME"
    
    echo ""
    echo -e "${GREEN}🎉 Multi-simulator setup complete!${NC}"
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo -e "  1. Both iPhone 15 simulators should have the app installed and running"
    echo -e "  2. App is configured for: $ENV_DESC"
    
    if [ "$ENV_MODE" = "STAGING" ]; then
        echo -e "  3. ${YELLOW}Pi server accessible via tunnel (URL may change on reboot)${NC}"
        if [ -n "$PI_TUNNEL_URL" ]; then
            echo -e "     Current tunnel: $PI_TUNNEL_URL"
        fi
    else
        echo -e "  3. ${YELLOW}Make sure your local server is running on port 3000${NC}"
    fi
    
    echo -e "  4. Register different player names on each simulator"
    echo -e "  5. Test multiplayer functionality between simulators"
else
    # Single simulator setup for AWS production
    boot_simulator "$SIM_UUID" "$SIM_NAME"
    
    echo -e "${BLUE}⏳ Waiting for simulator to stabilize...${NC}"
    sleep 3
    
    build_and_install "$SIM_UUID" "$SIM_NAME"
    
    echo ""
    echo -e "${GREEN}🎉 AWS production simulator setup complete!${NC}"
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo -e "  1. The iPhone SE simulator should have the app installed and running"
    echo -e "  2. App is configured for: $ENV_DESC"
    echo -e "  3. Register a player name on the simulator"
    echo -e "  4. Test app functionality with AWS infrastructure"
    echo -e "  5. Monitor AWS server logs for connection stability"
fi

echo ""
echo -e "${BLUE}💡 Tips and Troubleshooting:${NC}"
echo -e "  • Switch environments: ./build_multi_sim.sh [local|staging|aws]"
echo -e "  • Force clean build: ./build_multi_sim.sh [mode] --clean"
echo -e "  • Legacy support: LOCAL=1 ./build_multi_sim.sh still works"
echo -e "  • If app doesn't reflect code changes, try --clean flag"
echo -e "  • If still having cache issues, manually reset simulator: xcrun simctl erase [UUID]"
echo -e "  • For complete reset: shutdown simulator, erase, boot, then rebuild"
echo ""
echo -e "${YELLOW}🔧 Device Configuration:${NC}"
echo -e "  • Local Development: iPhone 15 + iPhone 15 Pro (fixed IP: 192.168.1.133)"
echo -e "  • Pi Staging: iPhone 15 + iPhone 15 Pro (tunnel URL changes on reboot)"
echo -e "  • AWS Production: iPhone SE (stable URL)"
echo -e "  • All modes support environment-aware networking configuration"

# Restore original NetworkConfiguration.swift
if [ -f "Models/Network/NetworkConfiguration.swift.backup" ]; then
    echo ""
    echo -e "${BLUE}🔄 Restoring original NetworkConfiguration.swift...${NC}"
    mv Models/Network/NetworkConfiguration.swift.backup Models/Network/NetworkConfiguration.swift
    echo -e "${GREEN}✅ Original NetworkConfiguration.swift restored${NC}"
fi