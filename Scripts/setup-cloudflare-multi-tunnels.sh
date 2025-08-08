#!/bin/bash
# Setup multiple Cloudflare tunnels for all services
# Each service gets its own tunnel URL!

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PI_HOST="192.168.1.222"
PI_USER="pi"

echo -e "${YELLOW}🤠 Setting up multiple Cloudflare tunnels on the Pi!${NC}"
echo -e "${YELLOW}   Each service will get its own URL!${NC}"

ssh $PI_USER@$PI_HOST << 'EOF'
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}📁 Creating tunnel configurations...${NC}"

# Create config directory
mkdir -p ~/.cloudflared

# Stop existing single tunnel if running
echo -e "${YELLOW}🛑 Stopping existing tunnel service...${NC}"
sudo systemctl stop cloudflare-tunnel || true
sudo systemctl disable cloudflare-tunnel || true

# Create startup scripts for each service
echo -e "${YELLOW}🎮 Creating Game Server tunnel (port 3000)...${NC}"
cat > ~/start-game-server-tunnel.sh << 'EOL'
#!/bin/bash
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:3000 2>&1 | tee /tmp/cloudflare-game-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-game-tunnel-url.txt
    echo "Game Server Tunnel: $TUNNEL_URL"
fi
tail -f /tmp/cloudflare-game-tunnel.log
EOL

echo -e "${YELLOW}📊 Creating Dashboard tunnel (port 3001)...${NC}"
cat > ~/start-dashboard-tunnel.sh << 'EOL'
#!/bin/bash
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:3001 2>&1 | tee /tmp/cloudflare-dashboard-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-dashboard-tunnel-url.txt
    echo "Dashboard Tunnel: $TUNNEL_URL"
fi
tail -f /tmp/cloudflare-dashboard-tunnel.log
EOL

echo -e "${YELLOW}🔗 Creating Link Generator tunnel (port 3002)...${NC}"
cat > ~/start-links-tunnel.sh << 'EOL'
#!/bin/bash
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:3002 2>&1 | tee /tmp/cloudflare-links-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-links-tunnel-url.txt
    echo "Links Tunnel: $TUNNEL_URL"
fi
tail -f /tmp/cloudflare-links-tunnel.log
EOL

echo -e "${YELLOW}🔧 Creating Admin Service tunnel (port 3003)...${NC}"
cat > ~/start-admin-tunnel.sh << 'EOL'
#!/bin/bash
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:3003 2>&1 | tee /tmp/cloudflare-admin-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-admin-tunnel-url.txt
    echo "Admin Tunnel: $TUNNEL_URL"
fi
tail -f /tmp/cloudflare-admin-tunnel.log
EOL

chmod +x ~/start-*-tunnel.sh

# Create systemd services for each tunnel
echo -e "${YELLOW}🚀 Creating systemd services...${NC}"

# Game Server tunnel service
sudo bash -c "cat > /etc/systemd/system/cloudflare-game-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Game Server Tunnel
After=network.target anagram-game.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-game-server-tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Dashboard tunnel service
sudo bash -c "cat > /etc/systemd/system/cloudflare-dashboard-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Dashboard Tunnel
After=network.target anagram-game.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-dashboard-tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Link Generator tunnel service
sudo bash -c "cat > /etc/systemd/system/cloudflare-links-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Link Generator Tunnel
After=network.target anagram-game.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-links-tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Admin Service tunnel service
sudo bash -c "cat > /etc/systemd/system/cloudflare-admin-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Admin Service Tunnel
After=network.target anagram-game.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-admin-tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Enable and start all services
echo -e "${YELLOW}🔧 Starting all tunnel services...${NC}"
sudo systemctl daemon-reload

for service in cloudflare-game-tunnel cloudflare-dashboard-tunnel cloudflare-links-tunnel cloudflare-admin-tunnel; do
    echo -e "${YELLOW}   Starting $service...${NC}"
    sudo systemctl enable $service
    sudo systemctl restart $service
done

# Wait for tunnels to establish
echo -e "${YELLOW}⏳ Waiting for tunnels to establish (30 seconds)...${NC}"
sleep 30

# Display all tunnel URLs
echo -e "${GREEN}🎉 All tunnels are set up! Here are your URLs:${NC}"
echo ""

if [ -f ~/cloudflare-game-tunnel-url.txt ]; then
    GAME_URL=$(cat ~/cloudflare-game-tunnel-url.txt)
    echo -e "${GREEN}🎮 Game Server: $GAME_URL${NC}"
else
    echo -e "${YELLOW}⏳ Game Server tunnel still starting...${NC}"
fi

if [ -f ~/cloudflare-dashboard-tunnel-url.txt ]; then
    DASHBOARD_URL=$(cat ~/cloudflare-dashboard-tunnel-url.txt)
    echo -e "${GREEN}📊 Web Dashboard: $DASHBOARD_URL${NC}"
else
    echo -e "${YELLOW}⏳ Dashboard tunnel still starting...${NC}"
fi

if [ -f ~/cloudflare-links-tunnel-url.txt ]; then
    LINKS_URL=$(cat ~/cloudflare-links-tunnel-url.txt)
    echo -e "${GREEN}🔗 Link Generator: $LINKS_URL${NC}"
else
    echo -e "${YELLOW}⏳ Links tunnel still starting...${NC}"
fi

if [ -f ~/cloudflare-admin-tunnel-url.txt ]; then
    ADMIN_URL=$(cat ~/cloudflare-admin-tunnel-url.txt)
    echo -e "${GREEN}🔧 Admin Service: $ADMIN_URL${NC}"
else
    echo -e "${YELLOW}⏳ Admin tunnel still starting...${NC}"
fi

echo ""
echo -e "${YELLOW}📌 All URLs are saved in ~/cloudflare-*-tunnel-url.txt files${NC}"
echo -e "${YELLOW}   They will persist across reboots!${NC}"

# Create a master script to show all URLs
cat > ~/show-tunnel-urls.sh << 'EOL'
#!/bin/bash
echo "🌐 Current Cloudflare Tunnel URLs:"
echo ""
[ -f ~/cloudflare-game-tunnel-url.txt ] && echo "🎮 Game Server: $(cat ~/cloudflare-game-tunnel-url.txt)"
[ -f ~/cloudflare-dashboard-tunnel-url.txt ] && echo "📊 Dashboard: $(cat ~/cloudflare-dashboard-tunnel-url.txt)"
[ -f ~/cloudflare-links-tunnel-url.txt ] && echo "🔗 Links: $(cat ~/cloudflare-links-tunnel-url.txt)"
[ -f ~/cloudflare-admin-tunnel-url.txt ] && echo "🔧 Admin: $(cat ~/cloudflare-admin-tunnel-url.txt)"
EOL
chmod +x ~/show-tunnel-urls.sh

# Update the main tunnel URL file to point to game server for backward compatibility
cp ~/cloudflare-game-tunnel-url.txt ~/cloudflare-tunnel-url.txt 2>/dev/null || true

EOF

echo -e "${GREEN}🎉 All done, partner!${NC}"
echo -e "${YELLOW}💡 To see all tunnel URLs anytime:${NC}"
echo "   ssh $PI_USER@$PI_HOST './show-tunnel-urls.sh'"