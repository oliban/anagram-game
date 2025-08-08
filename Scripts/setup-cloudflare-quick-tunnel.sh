#!/bin/bash
# Quick Cloudflare tunnel setup for staging
# No domain needed - free as a bird!

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PI_HOST="192.168.1.222"
PI_USER="pi"

echo -e "${YELLOW}🤠 Setting up Cloudflare quick tunnel on the Pi!${NC}"

ssh $PI_USER@$PI_HOST << 'EOF'
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}📁 Creating tunnel configuration...${NC}"

# Create config directory
mkdir -p ~/.cloudflared

# Create a config file for quick tunnel
cat > ~/.cloudflared/config.yml << 'EOL'
# Quick tunnel configuration
ingress:
  - service: http://localhost:3000
    originRequest:
      noTLSVerify: true
EOL

# Create startup script
cat > ~/start-cloudflare-tunnel.sh << 'EOL'
#!/bin/bash
# Get the tunnel URL and save it
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:3000 2>&1 | tee /tmp/cloudflare-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)

if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-tunnel-url.txt
    echo "Tunnel URL: $TUNNEL_URL"
fi

# Keep it running
tail -f /tmp/cloudflare-tunnel.log
EOL

chmod +x ~/start-cloudflare-tunnel.sh

# Create systemd service
echo -e "${YELLOW}🚀 Creating systemd service...${NC}"
sudo bash -c "cat > /etc/systemd/system/cloudflare-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Quick Tunnel
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-cloudflare-tunnel.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the service
echo -e "${YELLOW}🔧 Starting tunnel service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable cloudflare-tunnel
sudo systemctl restart cloudflare-tunnel

# Wait for it to start
sleep 10

# Get the tunnel URL
if [ -f ~/cloudflare-tunnel-url.txt ]; then
    TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt)
    echo -e "${GREEN}✅ Tunnel is running!${NC}"
    echo -e "${GREEN}🌐 Tunnel URL: $TUNNEL_URL${NC}"
else
    echo -e "${YELLOW}⏳ Waiting for tunnel URL...${NC}"
    sleep 5
    if [ -f ~/cloudflare-tunnel-url.txt ]; then
        TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt)
        echo -e "${GREEN}🌐 Tunnel URL: $TUNNEL_URL${NC}"
    fi
fi

# Show service status
sudo systemctl status cloudflare-tunnel --no-pager

echo -e "${GREEN}✅ Cloudflare tunnel service is set up!${NC}"
echo -e "${YELLOW}📌 The tunnel URL is saved in ~/cloudflare-tunnel-url.txt${NC}"
echo -e "${YELLOW}   It will persist across reboots!${NC}"

EOF

echo -e "${GREEN}🎉 All done, partner!${NC}"
echo -e "${YELLOW}💡 To get the current tunnel URL from your Pi:${NC}"
echo "   ssh $PI_USER@$PI_HOST 'cat ~/cloudflare-tunnel-url.txt'"