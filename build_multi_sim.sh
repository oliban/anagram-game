#!/bin/bash

# Build and launch Anagram Game with multi-device configuration
# 
# USAGE:
#   ./build_multi_sim.sh [aws|local] [--clean]
#
# ARGUMENTS:
#   local   - Deploy to iPhone 15 devices with local backend (default)
#   aws     - Deploy to iPhone SE with AWS backend
#   --clean - Force clean build (removes cache, slower but reliable)
#
# EXAMPLES:
#   ./build_multi_sim.sh                    # Local development (iPhone 15s)
#   ./build_multi_sim.sh local              # Local development (iPhone 15s)
#   ./build_multi_sim.sh aws                # AWS production (iPhone SE)
#   ./build_multi_sim.sh local --clean      # Local with clean build
#   ./build_multi_sim.sh aws --clean        # AWS with clean build
#
# DEVICE CONFIGURATION:
# - AWS MODE: iPhone SE for production testing
# - LOCAL MODE: iPhone 15 & iPhone 15 Pro for local development

set -e

# Parse command line arguments
ENV_MODE="LOCAL"  # Default
FORCE_CLEAN="0"

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
    --clean)
      FORCE_CLEAN="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [aws|local] [--clean]"
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
    # Local development uses iPhone 15 devices
    SIM1_UUID="AF307F12-A657-4D6A-8123-240CBBEC5B31"  # iPhone 15
    SIM2_UUID="86355D8A-560E-465D-8FDC-3D037BCA482B"  # iPhone 15 Pro
    SIM1_NAME="iPhone 15"
    SIM2_NAME="iPhone 15 Pro"
    USE_MULTI_SIM=true
else
    ENV_DESC="AWS cloud infrastructure"
    # AWS production uses iPhone SE
    SIM_UUID="046502C7-3D59-43F1-AA2D-EA2ADD0873B9"  # iPhone SE (3rd generation)
    SIM_NAME="iPhone SE (3rd generation)"
    USE_MULTI_SIM=false
fi

if [ "$USE_MULTI_SIM" = true ]; then
    echo "🚀 Building Anagram Game for local development (multi-simulator)..."
    echo "📱 Devices: $SIM1_NAME + $SIM2_NAME"
else
    echo "🚀 Building Anagram Game for AWS production (single simulator)..."
    echo "📱 Device: $SIM_NAME"
fi
echo "🌐 Environment: $ENV_DESC"

# Configuration
APP_NAME="Anagram Game"
SCHEME="Anagram Game"
PROJECT_FILE="Anagram Game.xcodeproj"
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📱 Using simulator(s):${NC}"
if [ "$USE_MULTI_SIM" = true ]; then
    echo -e "  $SIM1_NAME ($SIM1_UUID)"
    echo -e "  $SIM2_NAME ($SIM2_UUID)"
else
    echo -e "  $SIM_NAME ($SIM_UUID)"
fi
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
    if [ "$ENV_MODE" = "LOCAL" ]; then
        echo -e "${YELLOW}  • Setting USE_LOCAL_SERVER=true for parallel development${NC}"
        export USE_LOCAL_SERVER=true
    else
        echo -e "${BLUE}  • Setting USE_LOCAL_SERVER=false for AWS production${NC}"
        export USE_LOCAL_SERVER=false
    fi
    
    # Pass environment variable to xcodebuild
    USE_LOCAL_SERVER_VALUE="${USE_LOCAL_SERVER:-false}"
    
    xcodebuild -project "$PROJECT_FILE" \
               -scheme "$SCHEME" \
               -destination "platform=iOS Simulator,id=$uuid" \
               -configuration Debug \
               $BUILD_ACTION \
               USE_LOCAL_SERVER="$USE_LOCAL_SERVER_VALUE" \
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

# Note: Configuration is now embedded in AppConfig struct in NetworkManager.swift
# No need to generate Config.swift as it's not used anymore
echo -e "${BLUE}⚙️ Using embedded configuration (AppConfig in NetworkManager.swift)${NC}"

if [ "$USE_MULTI_SIM" = true ]; then
    # Multi-simulator setup for local development
    echo -e "${BLUE}🔄 Booting local development simulators...${NC}"
    boot_simulator "$SIM1_UUID" "$SIM1_NAME" &
    boot_simulator "$SIM2_UUID" "$SIM2_NAME" &
    wait
    
    echo -e "${BLUE}⏳ Waiting for simulators to stabilize...${NC}"
    sleep 5
    
    echo -e "${BLUE}🔨 Building and installing on both simulators...${NC}"
    build_and_install "$SIM1_UUID" "$SIM1_NAME" &
    build_and_install "$SIM2_UUID" "$SIM2_NAME" &
    wait
    
    echo ""
    echo -e "${GREEN}🎉 Multi-simulator setup complete!${NC}"
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo -e "  1. Both iPhone 15 simulators should have the app installed and running"
    echo -e "  2. App is configured for: $ENV_DESC"
    echo -e "  3. ${YELLOW}Make sure your local server is running on port 3000${NC}"
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
echo -e "  • Switch environments: ./build_multi_sim.sh aws  or  ./build_multi_sim.sh local"
echo -e "  • Force clean build: ./build_multi_sim.sh [local|aws] --clean"
echo -e "  • Legacy support: LOCAL=1 ./build_multi_sim.sh still works"
echo -e "  • If app doesn't reflect code changes, try --clean flag"
echo -e "  • If still having cache issues, manually reset simulator: xcrun simctl erase [UUID]"
echo -e "  • For complete reset: shutdown simulator, erase, boot, then rebuild"
echo ""
echo -e "${YELLOW}🔧 Device Configuration:${NC}"
echo -e "  • AWS Production: iPhone SE for final testing"
echo -e "  • Local Development: iPhone 15 + iPhone 15 Pro for parallel testing"
echo -e "  • Both modes support environment-aware networking configuration"