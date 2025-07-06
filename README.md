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
## 🎯 Game Rules

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
