#!/bin/bash
# Start local development environment with contribution web files
# Usage: ./start-local-dev.sh

set -e

echo "🚀 Starting local development environment..."

# Copy contribution web files to server/public/ if they exist
if [ -d "services/game-server/public" ]; then
    echo "📁 Copying contribution web files to server/public/..."
    mkdir -p server/public
    cp -r services/game-server/public/* server/public/
    echo "✅ Contribution web files copied"
else
    echo "⚠️  services/game-server/public not found, skipping web file copy"
fi

# Start Docker services
echo "🐳 Starting Docker services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 15

# Check if game server is healthy
if curl -s http://localhost:3000/api/status > /dev/null; then
    echo "✅ Game server is healthy"
else
    echo "❌ Game server is not responding"
fi

echo ""
echo "🎉 Local development environment ready!"
echo "🌐 Game API: http://localhost:3000"
echo "📊 API Documentation: http://localhost:3000/api-docs"
echo "🔗 Web Contribution: http://localhost:3000/contribute/{token}"
echo ""
echo "💡 To create a contribution link, use:"
echo "   curl -X POST http://localhost:3000/api/contribution/request -H 'Content-Type: application/json' -d '{\"playerId\": \"your-player-id\"}'"