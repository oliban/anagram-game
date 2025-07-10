# 🎯 Anagram Game

An immersive iOS anagram puzzle game built with SwiftUI and SpriteKit physics. Players drag and arrange letter tiles in a 3D bookshelf environment to form words from scrambled sentences.

## 🎮 Features

### Core Gameplay
- **Physics-Based Tiles**: Realistic letter tiles with momentum, friction, and collision detection
- **3D Bookshelf Environment**: Beautifully rendered isometric shelves and floor areas
- **Device Tilt Mechanics**: Tilt your iPhone forward to make tiles fall from shelves
- **Spatial Word Formation**: Arrange tiles physically to spell words left-to-right

## 📱 Supported Platforms

- **iOS**: iPhone (iOS 17.2+)

## 🏗️ Architecture

### SwiftUI + SpriteKit Hybrid
```
Views/
├── ContentView.swift          # Main app entry point
├── PhysicsGameView.swift      # Core game with SpriteKit integration
└── TileView.swift             # Individual tile components

Models/
├── GameModel.swift            # Observable game state and logic
└── Item.swift                 # Data structures

Resources/
├── anagrams.txt              # Game phrases (one per line)
└── Assets.xcassets/          # App icons and images
```

### Key Components

- **`PhysicsGameScene`**: SpriteKit scene handling physics simulation
- **`LetterTile`**: 3D-rendered physics-enabled tile sprites  
- **`GameModel`**: SwiftUI-observable game state management
- **Word Detection Algorithm**: Spatial arrangement validation system

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

# Open in Xcode
open "Anagram Game.xcodeproj"

# Build and run
⌘+R
```
## 🛠️ Backend Setup

This section guides you through setting up the server environment for the Anagram Game.

### Prerequisites
Ensure you have the following installed:

- Node.js 14.x or later
- PostgreSQL 12.x or later
- npm version 6.x or later

### Quick Setup (Recommended)

**Use the automated setup script located in the server directory:**
```bash
git clone git@github.com:oliban/anagram-game.git
cd anagram-game/server
./setup.sh
```

The setup script will automatically:
- Install Node.js dependencies
- Generate API documentation
- Create environment file from template
- Provide database setup instructions

### Manual Installation Steps

If you prefer to set up manually:

1. **Clone the Repository:**
   ```bash
   git clone git@github.com:oliban/anagram-game.git
   cd anagram-game/server
   ```

2. **Install Dependencies:**
   ```bash
   npm install
   ```

3. **Generate API Documentation:**
   ```bash
   npm run docs
   ```

4. **Environment Variables:**
   - Copy the example environment file:
     ```bash
     cp .env.example .env
     ```
   - Edit the `.env` file to include your database credentials and configuration options.

5. **Database Setup:**
   - Ensure PostgreSQL is running.
   - Initialize your database with the schema:
     ```bash
     psql -U <DB_USER> -d <DB_NAME> -f database/schema.sql
     ```

6. **Start the Server:**
   ```bash
   npm start
   # or directly with:
   node server.js
   ```

6. **API Documentation:**
   - Swagger documentation is available at: `http://localhost:<PORT>/api/docs`
   - Replace `<PORT>` with the port number specified in your `.env` file or default to `3000`.

Make sure to adapt the `<DB_USER>` and `<DB_NAME>` placeholders to your actual database username and name.

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
