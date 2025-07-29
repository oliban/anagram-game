#!/bin/bash

# Build and launch Anagram Game on multiple simulators for multiplayer testing
# 
# USAGE:
#   ./build_multi_sim.sh                    # Normal incremental build (fast)
#   FORCE_CLEAN=1 ./build_multi_sim.sh      # Aggressive clean build (slower)
#
# NORMAL MODE (default):
# - Fast incremental builds
# - Preserves derived data and existing app
# - Use for regular development
#
# FORCE_CLEAN MODE (when code changes aren't reflected):
# - Removes Xcode derived data cache
# - Uninstalls app before rebuilding  
# - Does clean build instead of incremental
# - Use when experiencing cache issues

set -e

echo "🚀 Building Anagram Game for multiple simulators..."

# Configuration
APP_NAME="Anagram Game"
SCHEME="Anagram Game"
PROJECT_FILE="Anagram Game.xcodeproj"
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"

# Simulator UUIDs (you can customize these)
SIM1_UUID="AF307F12-A657-4D6A-8123-240CBBEC5B31"  # iPhone 15
SIM2_UUID="86355D8A-560E-465D-8FDC-3D037BCA482B"  # iPhone 15 Pro
SIM3_UUID="046502C7-3D59-43F1-AA2D-EA2ADD0873B9"  # iPhone SE (3rd generation)
SIM1_NAME="iPhone 15"
SIM2_NAME="iPhone 15 Pro"
SIM3_NAME="iPhone SE (3rd generation)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📱 Using simulators:${NC}"
echo -e "  1. $SIM1_NAME ($SIM1_UUID)"
echo -e "  2. $SIM2_NAME ($SIM2_UUID)"
echo -e "  3. $SIM3_NAME ($SIM3_UUID)"
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
echo -e "${BLUE}🎯 Starting multi-simulator build process...${NC}"

# Check for force clean flag
if [ "$FORCE_CLEAN" = "1" ]; then
    force_clean_cache
fi

# Note: Configuration is now embedded in AppConfig struct in NetworkManager.swift
# No need to generate Config.swift as it's not used anymore
echo -e "${BLUE}⚙️ Using embedded configuration (AppConfig in NetworkManager.swift)${NC}"

# Boot all simulators
boot_simulator "$SIM1_UUID" "$SIM1_NAME"
boot_simulator "$SIM2_UUID" "$SIM2_NAME"
boot_simulator "$SIM3_UUID" "$SIM3_NAME"

echo -e "${BLUE}⏳ Waiting for simulators to stabilize...${NC}"
sleep 3

# Build and install on all simulators
build_and_install "$SIM1_UUID" "$SIM1_NAME"
echo ""
build_and_install "$SIM2_UUID" "$SIM2_NAME"
echo ""
build_and_install "$SIM3_UUID" "$SIM3_NAME"

echo ""
echo -e "${GREEN}🎉 Multi-simulator setup complete!${NC}"
echo -e "${YELLOW}📝 Next steps:${NC}"
echo -e "  1. Both simulators should have the app installed and running"
echo -e "  2. Register different player names on each simulator"
echo -e "  3. Test multiplayer functionality"
echo -e "  4. Monitor server logs for connection stability"
echo ""
echo -e "${BLUE}💡 Tips and Troubleshooting:${NC}"
echo -e "  • Modify simulator UUIDs in this script to use different devices"
echo -e "  • If app doesn't reflect code changes, run: FORCE_CLEAN=1 ./build_multi_sim.sh"
echo -e "  • If still having cache issues, manually reset simulator: xcrun simctl erase [UUID]"
echo -e "  • For complete reset: shutdown simulator, erase, boot, then rebuild"
echo ""
echo -e "${YELLOW}🔧 Common Cache Issues:${NC}"
echo -e "  • Xcode derived data can cache old builds"
echo -e "  • Simulator may keep old app versions installed"
echo -e "  • Use FORCE_CLEAN=1 flag to uninstall app before rebuilding"
echo -e "  • Last resort: completely reset simulator with erase command"