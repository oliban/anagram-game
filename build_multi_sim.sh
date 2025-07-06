#!/bin/bash

# Build and launch Anagram Game on multiple simulators for multiplayer testing
# Usage: ./build_multi_sim.sh

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
SIM1_NAME="iPhone 15"
SIM2_NAME="iPhone 15 Pro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📱 Using simulators:${NC}"
echo -e "  1. $SIM1_NAME ($SIM1_UUID)"
echo -e "  2. $SIM2_NAME ($SIM2_UUID)"
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

# Function to build and install app
build_and_install() {
    local uuid=$1
    local name=$2
    
    echo -e "${BLUE}🔨 Building for $name...${NC}"
    
    # Build for simulator
    xcodebuild -project "$PROJECT_FILE" \
               -scheme "$SCHEME" \
               -destination "platform=iOS Simulator,id=$uuid" \
               -configuration Debug \
               clean build \
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
        fi
    else
        echo -e "${RED}❌ Build failed for $name${NC}"
    fi
}

# Main execution
echo -e "${BLUE}🎯 Starting multi-simulator build process...${NC}"

# Boot both simulators
boot_simulator "$SIM1_UUID" "$SIM1_NAME"
boot_simulator "$SIM2_UUID" "$SIM2_NAME"

echo -e "${BLUE}⏳ Waiting for simulators to stabilize...${NC}"
sleep 3

# Build and install on both simulators
build_and_install "$SIM1_UUID" "$SIM1_NAME"
echo ""
build_and_install "$SIM2_UUID" "$SIM2_NAME"

echo ""
echo -e "${GREEN}🎉 Multi-simulator setup complete!${NC}"
echo -e "${YELLOW}📝 Next steps:${NC}"
echo -e "  1. Both simulators should have the app installed and running"
echo -e "  2. Register different player names on each simulator"
echo -e "  3. Test multiplayer functionality"
echo -e "  4. Monitor server logs for connection stability"
echo ""
echo -e "${BLUE}💡 Tip: You can modify the simulator UUIDs in this script to use different devices${NC}"