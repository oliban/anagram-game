#!/bin/bash

# Script to set the staging tunnel URL for the iOS app
# Usage: ./Scripts/set-staging-url.sh [tunnel-url]
#        ./Scripts/set-staging-url.sh auto  # Auto-detect from Pi

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PI_IP="192.168.1.222"

show_usage() {
    echo "Usage: $0 [tunnel-url|auto]"
    echo ""
    echo "Examples:"
    echo "  $0 https://example.trycloudflare.com"
    echo "  $0 auto    # Auto-detect tunnel URL from Pi"
    echo ""
    echo "This script updates NetworkConfiguration.swift with the current staging tunnel URL"
}

get_tunnel_url_from_pi() {
    echo -e "${YELLOW}🔍 Getting tunnel URL from Pi at ${PI_IP}...${NC}"
    
    # Try to get Cloudflare tunnel URL from Pi
    if ssh pi@${PI_IP} "test -f ~/cloudflare-tunnel-url.txt" 2>/dev/null; then
        local tunnel_url=$(ssh pi@${PI_IP} "cat ~/cloudflare-tunnel-url.txt" 2>/dev/null)
        if [ -n "$tunnel_url" ]; then
            echo -e "${GREEN}✅ Found Cloudflare tunnel URL: ${tunnel_url}${NC}"
            echo "$tunnel_url"
            return 0
        fi
    fi
    
    echo -e "${RED}❌ Could not get Cloudflare tunnel URL from Pi${NC}"
    echo -e "${YELLOW}💡 Make sure Pi is accessible and cloudflare-tunnel service is running${NC}"
    return 1
}

update_network_config() {
    local tunnel_url=$1
    local config_file="Models/Network/NetworkConfiguration.swift"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ NetworkConfiguration.swift not found${NC}"
        echo -e "${YELLOW}💡 Make sure you're running this from the project root${NC}"
        exit 1
    fi
    
    # Extract just the hostname from the URL
    local hostname=$(echo "$tunnel_url" | sed 's|https\?://||' | sed 's|/.*||')
    
    echo -e "${BLUE}🔧 Updating NetworkConfiguration.swift...${NC}"
    
    # Update the staging host configuration
    sed -i '' "s|let stagingConfig = EnvironmentConfig(host: \".*\", description: \"Pi Staging Server (tunnel URL)\")|let stagingConfig = EnvironmentConfig(host: \"$hostname\", description: \"Pi Staging Server (tunnel URL)\")|" "$config_file"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Updated staging configuration to use: $hostname${NC}"
        echo -e "${BLUE}💡 Next step: ./build_multi_sim.sh staging${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update configuration${NC}"
        return 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

case $1 in
    "auto")
        TUNNEL_URL=$(get_tunnel_url_from_pi)
        if [ $? -eq 0 ] && [ -n "$TUNNEL_URL" ]; then
            update_network_config "$TUNNEL_URL"
        else
            exit 1
        fi
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        # Validate URL format
        if [[ $1 =~ ^https?:// ]]; then
            update_network_config "$1"
        else
            echo -e "${RED}❌ Invalid URL format. Must start with http:// or https://${NC}"
            echo ""
            show_usage
            exit 1
        fi
        ;;
esac