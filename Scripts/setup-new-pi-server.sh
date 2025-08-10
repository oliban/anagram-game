#!/bin/bash

# Initial setup script for Raspberry Pi deployment
# WARNING: This script will WIPE all existing data and create a fresh installation
# Usage: ./scripts/setup-new-pi-server.sh [pi-hostname-or-ip]

set -e

PI_HOST=${1:-anagram-pi.local}
PI_USER="pi"
REMOTE_DIR="~/anagram-game"

echo "🚨 WARNING: This will WIPE all existing data on the Pi server!"
echo "   This script is for setting up a NEW server installation only."
echo "   For updates to existing servers, use the regular deployment process."
echo ""
read -p "   Are you sure you want to continue and wipe all data? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled"
    exit 1
fi

echo "🚀 Setting up NEW Raspberry Pi server at $PI_HOST..."

# Check if we can connect
echo "📡 Testing connection..."
if ! ssh -q $PI_USER@$PI_HOST exit; then
    echo "❌ Cannot connect to $PI_HOST"
    echo "Make sure:"
    echo "  - Pi is powered on and connected to network"
    echo "  - SSH is enabled"
    echo "  - You've added your SSH key: ssh-copy-id $PI_USER@$PI_HOST"
    exit 1
fi

echo "✅ Connection successful"

# Sync files (excluding node_modules, iOS build files, etc)
echo "📦 Syncing files..."
rsync -avz --delete \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude 'build' \
    --exclude 'DerivedData' \
    --exclude '*.xcworkspace' \
    --exclude '*.xcodeproj' \
    --exclude 'Pods' \
    --exclude '.env' \
    --exclude '.env.*' \
    --exclude 'postgres_data' \
    --exclude '*.log' \
    --exclude 'security-testing' \
    --exclude 'Models' \
    --exclude 'Views' \
    --exclude 'services' \
    --exclude 'Extensions' \
    --exclude 'Resources' \
    --exclude 'Fonts' \
    --exclude 'code_map.swift' \
    --exclude '.swiftlint.yml' \
    ./ $PI_USER@$PI_HOST:$REMOTE_DIR/

echo "🔧 Running initial setup on Pi..."
ssh $PI_USER@$PI_HOST << 'EOF'
    cd ~/anagram-game
    
    echo "🐳 Stopping any existing services..."
    docker-compose -f docker-compose.services.yml down || true
    
    echo "🗑️ WIPING all existing volumes for fresh installation..."
    docker volume ls | grep anagram | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
    docker system prune -f
    
    # Store current PostgreSQL version for future deployments
    grep -E "image: postgres:" docker-compose.services.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/' > .postgres_version
    
    echo "🔨 Building services..."
    docker-compose -f docker-compose.services.yml build
    
    echo "🚀 Starting services..."
    docker-compose -f docker-compose.services.yml up -d
    
    echo "⏳ Waiting for services to be healthy..."
    sleep 10
    
    echo "🗄️ Initializing database with complete schema..."
    # Apply complete schema including all tables and functions
    docker cp services/shared/database/schema.sql anagram-db:/tmp/
    docker cp services/shared/database/scoring_system_schema.sql anagram-db:/tmp/
    docker-compose -f docker-compose.services.yml exec -T postgres psql -U postgres -d anagram_game -f /tmp/schema.sql || true
    docker-compose -f docker-compose.services.yml exec -T postgres psql -U postgres -d anagram_game -f /tmp/scoring_system_schema.sql || true
    
    echo "🔍 Checking service status..."
    for port in 3000 3001 3002 3003; do
        if curl -s http://localhost:$port/api/status > /dev/null; then
            echo "✅ Service on port $port is healthy"
        else
            echo "❌ Service on port $port is not responding"
        fi
    done
    
    echo "📊 Container status:"
    docker ps
    
    echo "💾 Disk usage:"
    df -h | grep -E "^/dev/(root|sda|mmcblk)"
    
    echo "🧠 Memory usage:"
    free -h
EOF

echo "✅ NEW SERVER SETUP COMPLETE!"
echo ""
echo "📱 Update your iOS app configuration:"
echo "   1. Update NetworkConfiguration.swift with Pi tunnel URL"
echo "   2. Build and test with Pi server"
echo ""
echo "🌐 Access services:"
echo "   - Game API: http://$PI_HOST:3000"
echo "   - Dashboard: http://$PI_HOST:3001"
echo "   - Link Generator: http://$PI_HOST:3002"
echo "   - Admin: http://$PI_HOST:3003"
echo ""
echo "🔄 For future updates, use the regular deployment script which preserves data."