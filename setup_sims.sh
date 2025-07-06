#!/bin/bash

# Setup script to just boot and open the two simulators
# Use this first, then run the build script

set -e

# Configuration
SIM1_UUID="AF307F12-A657-4D6A-8123-240CBBEC5B31"  # iPhone 15
SIM2_UUID="86355D8A-560E-465D-8FDC-3D037BCA482B"  # iPhone 15 Pro
SIM1_NAME="iPhone 15"
SIM2_NAME="iPhone 15 Pro"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📱 Setting up simulators for multiplayer testing...${NC}"

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
    fi
    
    # Open Simulator app
    echo -e "${BLUE}📱 Opening $name in Simulator app...${NC}"
    open -a Simulator --args -CurrentDeviceUDID "$uuid"
    sleep 2
}

# Boot both simulators
boot_simulator "$SIM1_UUID" "$SIM1_NAME"
boot_simulator "$SIM2_UUID" "$SIM2_NAME"

echo -e "${GREEN}✅ Simulators are ready!${NC}"
echo -e "${YELLOW}💡 Next steps:${NC}"
echo -e "  1. Now run: ${BLUE}./build_multi_sim.sh${NC} to build and install the app"
echo -e "  2. Or use: ${BLUE}./quick_test.sh${NC} to just launch the app if already installed"