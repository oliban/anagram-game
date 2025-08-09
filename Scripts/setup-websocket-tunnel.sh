#!/bin/bash
# Setup Cloudflare tunnel with WebSocket support for multiplayer functionality
# This enables proper real-time multiplayer features

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PI_HOST="192.168.1.222"
PI_USER="pi"

echo -e "${YELLOW}🎮 Setting up Cloudflare tunnel with WebSocket support for multiplayer!${NC}"
echo ""

# Check if we can connect to the Pi
echo -e "${YELLOW}📡 Checking connection to Pi...${NC}"
if ! ssh -q $PI_USER@$PI_HOST exit; then
    echo -e "${RED}❌ Can't reach the Pi! Make sure it's powered up and ready!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Pi successfully!${NC}"

# Run the setup on the Pi
ssh $PI_USER@$PI_HOST << 'EOF'
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔧 Stopping existing tunnel services...${NC}"

# Stop any existing tunnel services
sudo systemctl stop cloudflare-tunnel 2>/dev/null || true
sudo systemctl stop cloudflared 2>/dev/null || true

echo -e "${YELLOW}📁 Creating WebSocket-enabled tunnel configuration...${NC}"

# Create config directory
mkdir -p ~/.cloudflared

# Create a config file with WebSocket support
cat > ~/.cloudflared/config.yml << 'EOL'
# WebSocket-enabled tunnel configuration for multiplayer games
ingress:
  - service: http://localhost:3000
    originRequest:
      noTLSVerify: true
      # Enable WebSocket upgrade support
      httpHostHeader: localhost:3000
      originServerName: localhost
      # Connection settings optimized for real-time gaming
      connectTimeout: 10s
      tlsTimeout: 10s
      tcpKeepAlive: 30s
      keepAliveTimeout: 90s
      keepAliveConnections: 100
      # Headers to ensure WebSocket upgrade works
      access:
        required: false
EOL

echo -e "${GREEN}✅ WebSocket configuration created!${NC}"

# Create enhanced startup script with WebSocket logging
cat > ~/start-websocket-tunnel.sh << 'EOL'
#!/bin/bash
echo "🚀 Starting Cloudflare tunnel with WebSocket support..."

# Start tunnel with enhanced logging
cloudflared tunnel --url http://localhost:3000 \
  --logfile /tmp/cloudflare-tunnel.log \
  --loglevel info 2>&1 | while IFS= read -r line; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
    
    # Extract and save tunnel URL
    if [[ $line == *"trycloudflare.com"* ]]; then
        TUNNEL_URL=$(echo "$line" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
        if [ -n "$TUNNEL_URL" ]; then
            echo "$TUNNEL_URL" > ~/cloudflare-tunnel-url.txt
            echo "✅ Tunnel URL saved: $TUNNEL_URL"
        fi
    fi
    
    # Log WebSocket connections
    if [[ $line == *"websocket"* ]] || [[ $line == *"WebSocket"* ]] || [[ $line == *"upgrade"* ]]; then
        echo "🔌 WebSocket event: $line"
    fi
done
EOL

chmod +x ~/start-websocket-tunnel.sh

# Create systemd service with WebSocket support
echo -e "${YELLOW}🚀 Creating WebSocket-enabled systemd service...${NC}"
sudo bash -c "cat > /etc/systemd/system/cloudflare-websocket-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Tunnel with WebSocket Support
After=network.target docker.service
Requires=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-websocket-tunnel.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflare-websocket

# Environment variables for WebSocket support
Environment="TUNNEL_ORIGIN_ENABLE_HTTP2=true"
Environment="TUNNEL_TRANSPORT_PROTOCOL=auto"

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the new service
echo -e "${YELLOW}🔧 Starting WebSocket-enabled tunnel service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable cloudflare-websocket-tunnel
sudo systemctl restart cloudflare-websocket-tunnel

# Wait for it to start and get URL
echo -e "${YELLOW}⏳ Waiting for tunnel to establish WebSocket connection...${NC}"
sleep 15

# Check status and get URL
if sudo systemctl is-active --quiet cloudflare-websocket-tunnel; then
    echo -e "${GREEN}✅ WebSocket-enabled tunnel is running!${NC}"
    
    if [ -f ~/cloudflare-tunnel-url.txt ]; then
        TUNNEL_URL=$(cat ~/cloudflare-tunnel-url.txt)
        echo -e "${GREEN}🌐 Tunnel URL: $TUNNEL_URL${NC}"
        echo -e "${GREEN}🎮 WebSocket support: ENABLED${NC}"
    else
        echo -e "${YELLOW}⏳ Still waiting for tunnel URL... checking logs...${NC}"
        # Show recent logs
        sudo journalctl -u cloudflare-websocket-tunnel --no-pager -n 10
    fi
else
    echo -e "${RED}❌ Tunnel service failed to start!${NC}"
    sudo systemctl status cloudflare-websocket-tunnel --no-pager
    echo -e "${YELLOW}📋 Recent logs:${NC}"
    sudo journalctl -u cloudflare-websocket-tunnel --no-pager -n 20
    exit 1
fi

echo -e "${GREEN}✅ WebSocket-enabled Cloudflare tunnel is set up!${NC}"
echo -e "${YELLOW}📌 The tunnel URL is saved in ~/cloudflare-tunnel-url.txt${NC}"
echo -e "${YELLOW}🎮 This tunnel supports WebSocket connections for multiplayer!${NC}"

EOF

echo ""
echo -e "${GREEN}🎉 WebSocket-enabled tunnel setup complete!${NC}"
echo -e "${YELLOW}💡 Key features enabled:${NC}"
echo "   ✅ WebSocket upgrade support"
echo "   ✅ Optimized for real-time gaming"
echo "   ✅ Enhanced connection timeouts"
echo "   ✅ WebSocket event logging"
echo ""
echo -e "${YELLOW}📋 To monitor WebSocket connections:${NC}"
echo "   ssh $PI_USER@$PI_HOST 'sudo journalctl -u cloudflare-websocket-tunnel -f'"
echo ""
echo -e "${YELLOW}🌐 To get the current tunnel URL:${NC}"
echo "   ssh $PI_USER@$PI_HOST 'cat ~/cloudflare-tunnel-url.txt'"