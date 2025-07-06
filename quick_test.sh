#!/bin/bash

# Quick test script for multiplayer connection stability
# This script just launches the app on two already-booted simulators

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

echo -e "${BLUE}🚀 Quick test: Launching app on both simulators...${NC}"

# Launch on both simulators
echo -e "${YELLOW}📱 Launching on $SIM1_NAME...${NC}"
xcrun simctl launch "$SIM1_UUID" com.fredrik.anagramgame 2>/dev/null || echo "App not installed on $SIM1_NAME"

echo -e "${YELLOW}📱 Launching on $SIM2_NAME...${NC}"
xcrun simctl launch "$SIM2_UUID" com.fredrik.anagramgame 2>/dev/null || echo "App not installed on $SIM2_NAME"

echo -e "${GREEN}✅ Quick test complete!${NC}"
echo -e "${YELLOW}💡 Use this script when you just want to relaunch the app on both simulators${NC}"