#!/bin/bash

# Deploy script for Raspberry Pi
# Usage: ./scripts/deploy-to-pi.sh [pi-hostname-or-ip]

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
LOCAL_PG_VERSION=$(grep -E "image: postgres:" docker-compose.services.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/')
PI_PG_VERSION=$(grep -E "image: postgres:" docker-compose.pi.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/')

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

echo "🔧 Running deployment on Pi..."
ssh $PI_USER@$PI_HOST << 'EOF'
    cd ~/anagram-game
    
    echo "🐳 Stopping current services..."
    docker-compose -f docker-compose.services.yml down || true
    
    echo "🗑️ Cleaning up old volumes to prevent version conflicts..."
    # Remove volumes if postgres version changed or if version mismatch was detected
    if [ -f .postgres_version ]; then
        PREV_VERSION=$(cat .postgres_version)
        CURRENT_VERSION=$(grep -E "image: postgres:" docker-compose.services.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/')
        if [ "$PREV_VERSION" != "$CURRENT_VERSION" ]; then
            echo "📋 PostgreSQL version changed from $PREV_VERSION to $CURRENT_VERSION"
            echo "🧹 Removing old database volumes for clean migration..."
            docker volume ls | grep anagram | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
        fi
    else
        # First deployment or missing version file - clean volumes for safety
        docker volume ls | grep anagram | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
    fi
    
    # Store current PostgreSQL version for future deployments
    grep -E "image: postgres:" docker-compose.services.yml | head -1 | sed 's/.*postgres:\([^[:space:]]*\).*/\1/' > .postgres_version
    
    echo "🔨 Building services..."
    docker-compose -f docker-compose.services.yml build
    
    echo "🚀 Starting services..."
    docker-compose -f docker-compose.services.yml up -d
    
    echo "⏳ Waiting for services to be healthy..."
    sleep 10
    
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
echo "   - Dashboard: http://$PI_HOST:3001"
echo "   - Link Generator: http://$PI_HOST:3002"
echo "   - Admin: http://$PI_HOST:3003"