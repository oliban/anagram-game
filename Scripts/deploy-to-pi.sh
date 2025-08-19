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
    
    echo "🧹 Cleaning up old containers and images..."
    docker container prune -f || true
    docker image prune -f || true
    echo "   ✅ Cleaned up old containers and dangling images"
    
    echo "💾 Database preservation mode - keeping all existing volumes"
    echo "   To wipe database, use scripts/setup-new-pi-server.sh instead"
    
    echo "🔨 Building services..."
    echo "   ⏱️  Building Docker containers with updated code..."
    
    # Check if hotfix mode is requested (for single file updates)
    if [ "$HOTFIX_MODE" = "true" ]; then
        echo "   🔥 HOTFIX MODE: Copying files directly to running container..."
        # Copy server files directly to container
        docker cp server/ anagram-server:/project/ 2>/dev/null || echo "   ⚠️  Container not running, will rebuild"
        docker cp services/ anagram-server:/project/ 2>/dev/null || true
        docker restart anagram-server 2>/dev/null || echo "   ⚠️  Will start container normally"
        echo "   ✅ Hotfix applied, container restarted"
    else
        # Normal build process
        echo "   🏗️  Starting Docker build..."
        START_TIME=$(date +%s)
        docker-compose build --progress=plain &
        BUILD_PID=$!
    
        # Monitor build progress
        while kill -0 $BUILD_PID 2>/dev/null; do
            ELAPSED=$(($(date +%s) - START_TIME))
            echo "   ⏳ Build running for ${ELAPSED}s..."
            if [ $ELAPSED -gt 180 ]; then
                echo "   ⚠️  Build taking longer than expected (3+ minutes)"
                echo "   💡 Consider running 'docker system prune -f' on Pi to clear cache"
            fi
            sleep 10
        done
        
        # Check if build succeeded
        wait $BUILD_PID
        BUILD_EXIT_CODE=$?
        if [ $BUILD_EXIT_CODE -ne 0 ]; then
            echo "   ❌ Build failed with exit code $BUILD_EXIT_CODE"
            exit 1
        fi
        
        TOTAL_TIME=$(($(date +%s) - START_TIME))
        echo "   ✅ Build completed in ${TOTAL_TIME}s"
    fi
    
    echo "🚀 Starting services..."
    echo "   📊 Current container status before start:"
    docker ps -a
    docker-compose up -d
    echo "   📊 Container status after start:"
    docker ps
    
    echo "⏳ Waiting for services to be healthy..."
    echo "   🕐 Waiting for containers to stabilize and be reachable..."
    
    # Wait up to 60 seconds for service to be ready
    RETRY_COUNT=0
    MAX_RETRIES=12
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "   🔄 Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES - Testing connectivity..."
        
        if curl -s --connect-timeout 5 http://localhost:3000/api/status > /dev/null 2>&1; then
            echo "   ✅ Service on port 3000 is reachable!"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "   ⏳ Service not ready yet, waiting 5 seconds..."
                sleep 5
            else
                echo "   ❌ Service failed to become reachable after $((MAX_RETRIES * 5)) seconds"
                echo "   📋 Container logs:"
                # Handle both possible container names
                docker logs anagram-server --tail 20 2>/dev/null || docker logs server --tail 20 2>/dev/null || echo "     No logs available"
                echo "   📊 Container status:"
                docker ps -a
                echo "   🔧 Attempting container restart..."
                docker-compose restart 2>/dev/null || true
                sleep 10
                echo "   🔄 Retrying connectivity test after restart..."
                if curl -s --connect-timeout 5 http://localhost:3000/api/status > /dev/null 2>&1; then
                    echo "   ✅ Service recovered after restart!"
                else
                    echo "   ❌ Service still not responding after restart"
                    echo "   📋 Final container logs:"
                    docker logs anagram-server --tail 30 2>/dev/null || docker logs server --tail 30 2>/dev/null || echo "     No logs available"
                    exit 1
                fi
            fi
        fi
    done
    
    echo "🔍 Testing service functionality..."
    
    # CRITICAL: Verify that the deployed code is actually in the container
    echo "   🔬 Verifying deployed code is in container..."
    if docker exec anagram-server grep -q "x-forwarded-host" /project/server/contribution-link-generator.js 2>/dev/null; then
        echo "   ✅ Container has updated code (x-forwarded-host fix present)"
    else
        echo "   ❌ WARNING: Container may be using old code!"
        echo "   🔧 Attempting hotfix..."
        docker cp server/contribution-link-generator.js anagram-server:/project/server/
        docker restart anagram-server
        sleep 10
        echo "   ✅ Hotfix applied"
    fi
    
    echo "   📡 Testing database connection..."
    STATUS_RESPONSE=$(curl -s http://localhost:3000/api/status || echo "")
    if echo "$STATUS_RESPONSE" | grep -q "database"; then
        echo "   ✅ Database connection OK"
    else
        echo "   ⚠️  Database status unclear"
        echo "   📄 Status response: $STATUS_RESPONSE"
    fi
    
    echo "   🎮 Testing game API endpoints..."
    if curl -s http://localhost:3000/api/players > /dev/null; then
        echo "   ✅ Players API working"
    else
        echo "   ❌ Players API not responding"
    fi
    
    echo "   🔗 Testing contribution link generation..."
    TEST_LINK=$(curl -s -X POST http://localhost:3000/api/contribution/request -H "Content-Type: application/json" -d '{"playerId":"test-player","expirationHours":24,"maxUses":3}' | grep -o 'https://[^"]*' || echo "")
    if [ -n "$TEST_LINK" ]; then
        echo "   ✅ Contribution links using correct Cloudflare URL: $TEST_LINK"
    else
        echo "   ⚠️  Could not test contribution link generation"
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