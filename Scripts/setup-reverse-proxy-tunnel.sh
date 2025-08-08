#!/bin/bash
# Setup Cloudflare tunnel with nginx reverse proxy
# This replaces individual service tunnels with one clean proxy setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PI_HOST="192.168.1.222"
PI_USER="pi"

echo -e "${YELLOW}🤠 Setting up reverse proxy tunnel solution, partner!${NC}"
echo -e "${YELLOW}   This'll give us one clean tunnel for all services!${NC}"

# Function to deploy the nginx configuration
deploy_nginx_config() {
    echo -e "${BLUE}📁 Deploying nginx configuration and docker-compose to Pi...${NC}"
    
    # Copy nginx config and docker-compose file
    scp nginx.conf $PI_USER@$PI_HOST:~/nginx.conf
    scp docker-compose.nginx.yml $PI_USER@$PI_HOST:~/docker-compose.nginx.yml
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Configuration files deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy configuration files${NC}"
        return 1
    fi
}

# Function to setup services on Pi
setup_pi_services() {
    echo -e "${BLUE}🚀 Setting up services on Pi...${NC}"
    
    ssh $PI_USER@$PI_HOST << 'EOF'
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Stopping old individual tunnel services...${NC}"

# Stop all old tunnel services
for service in cloudflare-game-tunnel cloudflare-dashboard-tunnel cloudflare-links-tunnel cloudflare-admin-tunnel cloudflare-tunnel; do
    if systemctl is-enabled $service >/dev/null 2>&1; then
        echo -e "${YELLOW}   Stopping and disabling $service...${NC}"
        sudo systemctl stop $service || true
        sudo systemctl disable $service || true
    fi
done

echo -e "${YELLOW}🧹 Cleaning up old tunnel files...${NC}"
rm -f ~/cloudflare-*-tunnel-url.txt ~/start-*-tunnel.sh ~/show-tunnel-urls.sh

echo -e "${YELLOW}🐳 Stopping old docker services...${NC}"
docker-compose -f docker-compose.services.yml down || true

echo -e "${YELLOW}🚀 Starting nginx reverse proxy setup...${NC}"

# Start the new nginx-based setup
docker-compose -f docker-compose.nginx.yml up -d

# Wait for services to be healthy
echo -e "${YELLOW}⏳ Waiting for services to start up (30 seconds)...${NC}"
sleep 30

# Check service health
echo -e "${YELLOW}🔍 Checking service health...${NC}"
if docker-compose -f docker-compose.nginx.yml ps | grep -q "healthy"; then
    echo -e "${GREEN}✅ Services are starting up successfully${NC}"
else
    echo -e "${RED}⚠️  Some services may still be starting...${NC}"
fi

# Show service status
echo -e "${BLUE}📊 Service Status:${NC}"
docker-compose -f docker-compose.nginx.yml ps

EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Pi services setup completed${NC}"
    else
        echo -e "${RED}❌ Failed to setup Pi services${NC}"
        return 1
    fi
}

# Function to create the new tunnel
create_reverse_proxy_tunnel() {
    echo -e "${BLUE}🌐 Creating single Cloudflare tunnel to nginx proxy...${NC}"
    
    ssh $PI_USER@$PI_HOST << 'EOF'
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🌍 Setting up single Cloudflare tunnel to port 80 (nginx)...${NC}"

# Create the tunnel startup script
cat > ~/start-reverse-proxy-tunnel.sh << 'EOL'
#!/bin/bash
echo "🌐 Starting Cloudflare tunnel to nginx reverse proxy..."
TUNNEL_OUTPUT=$(cloudflared tunnel --url http://localhost:80 2>&1 | tee /tmp/cloudflare-reverse-proxy-tunnel.log)
TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -o 'https://[^[:space:]]*\.trycloudflare\.com' | head -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "$TUNNEL_URL" > ~/cloudflare-reverse-proxy-url.txt
    echo "🎉 Reverse Proxy Tunnel: $TUNNEL_URL"
    echo ""
    echo "📍 Service endpoints:"
    echo "  🎮 Game API: $TUNNEL_URL/api/"
    echo "  📊 Dashboard: $TUNNEL_URL/dashboard"
    echo "  🔗 Links: $TUNNEL_URL/links"  
    echo "  🔧 Admin: $TUNNEL_URL/admin"
    echo "  ❤️ Health: $TUNNEL_URL/nginx-status"
fi
tail -f /tmp/cloudflare-reverse-proxy-tunnel.log
EOL

chmod +x ~/start-reverse-proxy-tunnel.sh

# Create systemd service for the tunnel
sudo bash -c "cat > /etc/systemd/system/cloudflare-reverse-proxy-tunnel.service" << 'EOL'
[Unit]
Description=Cloudflare Reverse Proxy Tunnel
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/start-reverse-proxy-tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the tunnel service
echo -e "${YELLOW}🔧 Starting reverse proxy tunnel service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable cloudflare-reverse-proxy-tunnel
sudo systemctl start cloudflare-reverse-proxy-tunnel

# Wait for tunnel to establish
echo -e "${YELLOW}⏳ Waiting for tunnel to establish (15 seconds)...${NC}"
sleep 15

# Display the tunnel URL
if [ -f ~/cloudflare-reverse-proxy-url.txt ]; then
    TUNNEL_URL=$(cat ~/cloudflare-reverse-proxy-url.txt)
    echo -e "${GREEN}🎉 Reverse proxy tunnel established!${NC}"
    echo ""
    echo -e "${BLUE}🌐 Main URL: ${TUNNEL_URL}${NC}"
    echo ""
    echo -e "${GREEN}📍 Service endpoints:${NC}"
    echo -e "${GREEN}  🎮 Game API: ${TUNNEL_URL}/api/${NC}"
    echo -e "${GREEN}  📊 Dashboard: ${TUNNEL_URL}/dashboard${NC}"
    echo -e "${GREEN}  🔗 Links: ${TUNNEL_URL}/links${NC}"
    echo -e "${GREEN}  🔧 Admin: ${TUNNEL_URL}/admin${NC}"
    echo -e "${GREEN}  ❤️ Health Check: ${TUNNEL_URL}/nginx-status${NC}"
    echo ""
    
    # Also update the main tunnel URL file for backward compatibility
    cp ~/cloudflare-reverse-proxy-url.txt ~/cloudflare-tunnel-url.txt
else
    echo -e "${YELLOW}⏳ Tunnel still establishing, check status with:${NC}"
    echo "   ssh $USER@$(hostname -I | cut -d' ' -f1) 'sudo systemctl status cloudflare-reverse-proxy-tunnel'"
fi

# Create helper script to show tunnel URL
cat > ~/show-reverse-proxy-url.sh << 'EOL'
#!/bin/bash
if [ -f ~/cloudflare-reverse-proxy-url.txt ]; then
    TUNNEL_URL=$(cat ~/cloudflare-reverse-proxy-url.txt)
    echo "🌐 Reverse Proxy Tunnel URL: $TUNNEL_URL"
    echo ""
    echo "📍 Service endpoints:"
    echo "  🎮 Game API: $TUNNEL_URL/api/"
    echo "  📊 Dashboard: $TUNNEL_URL/dashboard" 
    echo "  🔗 Links: $TUNNEL_URL/links"
    echo "  🔧 Admin: $TUNNEL_URL/admin"
    echo "  ❤️ Health: $TUNNEL_URL/nginx-status"
else
    echo "❌ Tunnel URL not found. Check if tunnel is running:"
    echo "   sudo systemctl status cloudflare-reverse-proxy-tunnel"
fi
EOL
chmod +x ~/show-reverse-proxy-url.sh

EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Reverse proxy tunnel setup completed${NC}"
    else
        echo -e "${RED}❌ Failed to setup reverse proxy tunnel${NC}"
        return 1
    fi
}

# Main execution
echo -e "${YELLOW}🎯 Step 1: Deploy configuration files${NC}"
deploy_nginx_config

echo -e "${YELLOW}🎯 Step 2: Setup Pi services${NC}"
setup_pi_services

echo -e "${YELLOW}🎯 Step 3: Create reverse proxy tunnel${NC}"
create_reverse_proxy_tunnel

echo -e "${GREEN}🎉 Reverse proxy tunnel setup complete, partner!${NC}"
echo ""
echo -e "${BLUE}💡 To check the tunnel URL anytime:${NC}"
echo "   ssh $PI_USER@$PI_HOST './show-reverse-proxy-url.sh'"
echo ""
echo -e "${BLUE}💡 To check service status:${NC}"
echo "   ssh $PI_USER@$PI_HOST 'docker-compose -f docker-compose.nginx.yml ps'"