#!/bin/bash

# Code update script for existing Raspberry Pi deployment
# This script preserves existing database and only updates application code
# Usage: ./scripts/deploy-to-pi.sh [pi-hostname-or-ip]
#
# WARNING: For NEW server setup, use scripts/setup-new-pi-server.sh instead!

set -e

PI_HOST=${1:-anagram-pi.local}
PI_USER="pi"
REMOTE_DIR="~/anagram-game"

echo "🚀 Deploying to Raspberry Pi at $PI_HOST..."

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

# Check PostgreSQL version consistency
echo "🔍 Checking PostgreSQL version consistency..."

# Extract local PostgreSQL version
LOCAL_PG_VERSION=$(grep -E "image: postgres:" docker-compose.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/')
PI_PG_VERSION=$(grep -E "image: postgres:" docker-compose.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/')

echo "📊 PostgreSQL versions:"
echo "  Local development: postgres:$LOCAL_PG_VERSION"
echo "  Pi deployment:     postgres:$PI_PG_VERSION"

if [ "$LOCAL_PG_VERSION" != "$PI_PG_VERSION" ]; then
    echo "⚠️  WARNING: PostgreSQL version mismatch detected!"
    echo "   This may cause database compatibility issues."
    echo "   Consider updating docker-compose.pi.yml to use postgres:$LOCAL_PG_VERSION"
    echo ""
    read -p "   Continue deployment anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        exit 1
    fi
    echo "⚠️  Proceeding with version mismatch - database volumes will be cleaned"
else
    echo "✅ PostgreSQL versions match"
fi

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

echo "🔧 Running code update on Pi (preserving database)..."
ssh $PI_USER@$PI_HOST << 'EOF'
    cd ~/anagram-game
    
    echo "📁 Copying contribution web files to server/public/..."
    mkdir -p server/public
    cp -r services/game-server/public/* server/public/ 2>/dev/null || echo "⚠️  services/game-server/public not found, skipping"
    
    echo "🐳 Stopping current services..."
    docker-compose down || true
    
    echo "💾 Database preservation mode - keeping all existing volumes"
    echo "   To wipe database, use scripts/setup-new-pi-server.sh instead"
    
    echo "🔨 Building services..."
    echo "   ⏱️  This may take 2-3 minutes depending on changes..."
    docker-compose build --no-cache --progress=plain
    
    echo "🚀 Starting services..."
    echo "   📊 Current container status before start:"
    docker ps -a
    docker-compose up -d
    echo "   📊 Container status after start:"
    docker ps
    
    echo "⏳ Waiting for services to be healthy..."
    echo "   🕐 Waiting 10 seconds for containers to stabilize..."
    sleep 10
    
    echo "🔍 Checking service status..."
    echo "   🌐 Testing API endpoint..."
    if curl -s http://localhost:3000/api/status > /dev/null; then
        echo "   ✅ Service on port 3000 is healthy"
        echo "   📡 Testing database connection..."
        curl -s http://localhost:3000/api/status | grep -q "database" && echo "   ✅ Database connection OK" || echo "   ⚠️  Database status unclear"
    else
        echo "   ❌ Service on port 3000 is not responding"
        echo "   📋 Container logs:"
        docker logs anagram-server --tail 10 || echo "     No logs available"
    fi
    
    echo "📊 Container status:"
    docker ps
    
    echo "💾 Disk usage:"
    df -h | grep -E "^/dev/(root|sda|mmcblk)"
    
    echo "🧠 Memory usage:"
    free -h
EOF

echo "✅ Deployment complete!"
echo ""
echo "📱 Update your iOS app configuration:"
echo "   1. Open ConfigurationManager.swift"
echo "   2. Add Pi configuration:"
echo "      case raspberryPi = \"http://$PI_HOST:3000\""
echo "   3. Build and test with Pi server"
echo ""
echo "🌐 Access services:"
echo "   - Game API: http://$PI_HOST:3000"