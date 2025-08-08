#!/bin/bash
# Setup script for Cloudflare tunnel on Raspberry Pi
# Y'all gonna love how smooth this runs!

set -e

# Colors prettier than a sunset
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PI_HOST="192.168.1.222"
PI_USER="pi"

echo -e "${YELLOW}🤠 Howdy! Let's set up that Cloudflare tunnel, partner!${NC}"
echo ""

# Check if we can connect to the Pi
echo -e "${YELLOW}📡 Checking connection to Pi...${NC}"
if ! ssh -q $PI_USER@$PI_HOST exit; then
    echo -e "${RED}❌ Can't reach the Pi! Make sure it's powered up and ready!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Pi like butter on biscuit!${NC}"

# Run the setup on the Pi
ssh $PI_USER@$PI_HOST << 'EOF'
set -e

# Colors for the Pi side
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔧 Setting up Cloudflare tunnel on the Pi...${NC}"

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    echo -e "${RED}❌ cloudflared ain't installed yet!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ cloudflared is installed and ready to roll!${NC}"

# Create config directory if it doesn't exist
mkdir -p ~/.cloudflared

# Check if we already have a tunnel
if [ -f ~/.cloudflared/cert.pem ]; then
    echo -e "${YELLOW}🔑 Found existing Cloudflare credentials${NC}"
else
    echo -e "${YELLOW}🌐 Time to authenticate with Cloudflare...${NC}"
    echo -e "${YELLOW}   This'll open a browser - login to your Cloudflare account${NC}"
    cloudflared tunnel login
fi

# Check for existing tunnel
EXISTING_TUNNEL=$(cloudflared tunnel list 2>/dev/null | grep "anagram-staging" || true)

if [ -n "$EXISTING_TUNNEL" ]; then
    echo -e "${YELLOW}🚇 Found existing tunnel: anagram-staging${NC}"
    TUNNEL_ID=$(echo "$EXISTING_TUNNEL" | awk '{print $1}')
else
    echo -e "${YELLOW}🚇 Creating new tunnel: anagram-staging${NC}"
    cloudflared tunnel create anagram-staging
    TUNNEL_ID=$(cloudflared tunnel list | grep "anagram-staging" | awk '{print $1}')
fi

echo -e "${GREEN}✅ Tunnel ID: $TUNNEL_ID${NC}"

# Create the config file
echo -e "${YELLOW}📝 Writing tunnel configuration...${NC}"
cat > ~/.cloudflared/config.yml << EOL
tunnel: $TUNNEL_ID
credentials-file: /home/pi/.cloudflared/${TUNNEL_ID}.json

ingress:
  # Game server
  - hostname: anagram-staging.trycloudflare.com
    service: http://localhost:3000
    originRequest:
      noTLSVerify: true
  # Web dashboard  
  - hostname: anagram-dashboard.trycloudflare.com
    service: http://localhost:3001
    originRequest:
      noTLSVerify: true
  # Link generator
  - hostname: anagram-links.trycloudflare.com
    service: http://localhost:3002
    originRequest:
      noTLSVerify: true
  # Admin service
  - hostname: anagram-admin.trycloudflare.com
    service: http://localhost:3003
    originRequest:
      noTLSVerify: true
  # Catch-all
  - service: http_status:404
EOL

echo -e "${GREEN}✅ Configuration written!${NC}"

# Get the tunnel URL
echo -e "${YELLOW}🌐 Getting tunnel URL...${NC}"
TUNNEL_URL=$(cloudflared tunnel info $TUNNEL_ID --output json | jq -r '.connections[0].pub_url' 2>/dev/null || echo "")

if [ -z "$TUNNEL_URL" ]; then
    # Tunnel not running yet, we'll get a trycloudflare.com URL when it starts
    TUNNEL_URL="https://${TUNNEL_ID}.cfargotunnel.com"
    echo -e "${YELLOW}📌 Tunnel will be available at: $TUNNEL_URL${NC}"
else
    echo -e "${GREEN}📌 Tunnel URL: $TUNNEL_URL${NC}"
fi

# Create systemd service
echo -e "${YELLOW}🚀 Creating systemd service...${NC}"
sudo bash -c "cat > /etc/systemd/system/cloudflared.service" << EOL
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=notify
User=pi
Group=pi
ExecStart=/usr/bin/cloudflared tunnel run
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared
Environment="HOME=/home/pi"

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the service
echo -e "${YELLOW}🔧 Enabling cloudflared service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared

# Wait a bit for it to start
sleep 5

# Check if it's running
if sudo systemctl is-active --quiet cloudflared; then
    echo -e "${GREEN}✅ Cloudflare tunnel is running like a well-oiled machine!${NC}"
    
    # Try to get the actual URL
    echo -e "${YELLOW}🔍 Fetching tunnel details...${NC}"
    cloudflared tunnel info $TUNNEL_ID
else
    echo -e "${RED}❌ Tunnel service failed to start!${NC}"
    sudo systemctl status cloudflared
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Yeehaw! Cloudflare tunnel is all set up!${NC}"
echo -e "${YELLOW}📌 Your staging URL: https://${TUNNEL_ID}.cfargotunnel.com${NC}"
echo -e "${YELLOW}   (It might take a minute to be accessible)${NC}"

EOF

echo ""
echo -e "${GREEN}🤠 All done, partner! Your Cloudflare tunnel is ready to ride!${NC}"
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "   1. Update NetworkConfiguration.swift with the new URL"
echo "   2. Update build scripts to use Cloudflare instead of ngrok"
echo "   3. Test the staging build"
echo ""