# 🎯 Wordshelf

An immersive iOS multiplayer word game built with SwiftUI and SpriteKit physics. Players drag and arrange letter tiles in a 3D bookshelf environment to form words from scrambled sentences.

## 🎮 Features

### Core Gameplay
- **Physics-Based Tiles**: Realistic letter tiles with momentum, friction, and collision detection
- **3D Bookshelf Environment**: Beautifully rendered isometric shelves and floor areas
- **Device Tilt Mechanics**: Tilt your iPhone forward to make tiles fall from shelves
- **Spatial Word Formation**: Arrange tiles physically to spell words left-to-right

### Multiplayer & Social
- **Real-time Multiplayer**: Play with friends via WebSocket connections
- **Global Leaderboards**: Daily, weekly, and all-time rankings
- **Custom Phrase Contributions**: Share puzzles with friends via contribution links
- **Player Statistics**: Track progress and achievements

## 📱 Supported Platforms

- **iOS**: iPhone (iOS 17.2+)

## 🏗️ Architecture

### iOS Client (SwiftUI + SpriteKit)
```
Views/
├── ContentView.swift          # Main app entry point
├── PhysicsGameView.swift      # Core game with SpriteKit integration
├── LobbyView.swift           # Multiplayer lobby interface
└── TileView.swift             # Individual tile components

Models/
├── GameModel.swift            # Observable game state and logic
├── NetworkManager.swift      # API and WebSocket connections
└── Item.swift                 # Data structures

Services/
├── Network/PlayerService.swift    # Player operations
├── Network/PhraseService.swift    # Phrase operations
└── shared/DebugLogger.swift       # Cross-service logging
```

### Backend Services (Docker + Node.js)
```
services/
├── game-server/              # Core API + WebSocket + contributions (port 3000)
├── web-dashboard/           # Monitoring interface (port 3001)  
├── admin-service/          # Content management (port 3003)
└── shared/                 # Database models & utilities
```

### Key Components

**iOS Client:**
- **`PhysicsGameScene`**: SpriteKit scene handling physics simulation
- **`LetterTile`**: 3D-rendered physics-enabled tile sprites  
- **`GameModel`**: SwiftUI-observable game state management
- **`NetworkManager`**: Real-time multiplayer connectivity

**Backend Services:**
- **Game Server**: Multiplayer API, WebSocket, phrase contributions
- **Web Dashboard**: Real-time monitoring and analytics
- **Admin Service**: Content management and batch operations
- **PostgreSQL**: Shared database with automated leaderboards

## 🔧 Development Setup

### Prerequisites
- Xcode 15.0+
- iOS 17.2+ SDK
- Swift 5.9+

### Getting Started
```bash
# Clone the repository
git clone git@github.com:oliban/anagram-game.git
cd anagram-game

# Build iOS app with backend services
./build_multi_sim.sh local          # Local development build
```

## 🛠️ Backend Setup

This section guides you through setting up the microservices environment.

### Prerequisites
Ensure you have the following installed:

- Docker Desktop
- Node.js 18.x or later  
- PostgreSQL (via Docker)

### Quick Setup (Recommended)

**Start all backend services:**
```bash
# Start PostgreSQL + all microservices
docker-compose -f docker-compose.services.yml up -d

# Verify services are healthy
docker-compose -f docker-compose.services.yml ps
```

**Services Available:**
- **Game Server**: http://localhost:3000 (API + WebSocket + Contributions)
- **Web Dashboard**: http://localhost:3001 (Monitoring)
- **Admin Service**: http://localhost:3003 (Content Management)
- **PostgreSQL**: localhost:5432

### Development Workflow

```bash
# One-command deployment
./build_multi_sim.sh local          # Local development
./scripts/deploy-staging.sh         # Complete Pi staging deployment
./build_multi_sim.sh aws            # AWS production

# Run comprehensive tests
node testing/scripts/automated-test-runner.js

# Monitor services
docker-compose -f docker-compose.services.yml logs -f

# Database access
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game
```

### Environment Configuration

Copy and customize the environment file:
```bash
cp .env.example .env
```

Key environment variables:
- `GAME_SERVER_PORT=3000`
- `WEB_DASHBOARD_PORT=3001`  
- `ADMIN_SERVICE_PORT=3003`
- `DB_NAME=anagram_game`
- `SECURITY_RELAXED=true` (development only)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`⌘+U` in Xcode)
4. Commit changes (`git commit -m 'Add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is open source. See individual file headers for specific licensing.

## 🎉 Acknowledgments

- Built with guidance from Claude Code AI assistant
- Inspired by classic word puzzle games
- Physics simulation powered by SpriteKit
- UI framework provided by SwiftUI

---

**Developed with ❤️ for iOS**
