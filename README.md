# 🎯 Anagram Game

An immersive iOS anagram puzzle game built with SwiftUI and SpriteKit physics. Players drag and arrange letter tiles in a 3D bookshelf environment to form words from scrambled sentences.

## 🎮 Features

### Core Gameplay
- **Physics-Based Tiles**: Realistic letter tiles with momentum, friction, and collision detection
- **3D Bookshelf Environment**: Beautifully rendered isometric shelves and floor areas
- **Device Tilt Mechanics**: Tilt your iPhone forward to make tiles fall from shelves
- **Spatial Word Formation**: Arrange tiles physically to spell words left-to-right

### Smart Word Detection
- **Level-Based Validation**: Words must be formed by tiles on the same horizontal level
- **Companion Tile System**: Lonely tiles without companions at their Y-level are excluded
- **Precise Spatial Ordering**: Only accepts tiles that spell words correctly when read left-to-right
- **Anti-Stacking Logic**: Prevents false victories from stacked or misaligned tiles

### Game Experience  
- **Celebration Animations**: Fireworks and congratulatory messages for victories
- **Play Again System**: Seamlessly restart with new random phrases
- **Portrait Mode Only**: Optimized for iPhone portrait orientation
- **Comprehensive Testing**: Unit tests for core game logic and edge cases

## 📱 Supported Platforms

- **iOS**: iPhone (iOS 17.2+)
- **Apple Watch**: Simplified version (planned)

## 🎯 Sample Phrases

- "I love you"
- "one job" 
- "two parties"

*More phrases can be added to `Resources/anagrams.txt`*

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

## 🧪 Testing

Comprehensive unit test suite covering:

```bash
# Run tests in Xcode
⌘+U

# Test categories:
- Tile selection algorithm (duplicate letter handling)
- Spatial word formation validation  
- Level-based grouping logic
- Game state management
- Performance with many tiles
```

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

### Development Commands
- **Build**: `⌘+B`
- **Run**: `⌘+R` 
- **Test**: `⌘+U`
- **Clean**: `⌘+Shift+K`

## 🎯 Game Rules

### Word Formation
1. **Drag tiles** to arrange them on shelves or floor
2. **Tiles must have companions** - lonely tiles at isolated Y-levels are excluded
3. **Read left-to-right** - spatial arrangement determines spelling
4. **Same level only** - all letters of a word must be on the same horizontal level

### Physics Mechanics
- **Normal Mode**: Standard gravity, tiles settle naturally
- **Falling Mode**: Tilt device forward (Y < -0.90) to make shelf tiles fall
- **No Sliding**: Tiles stop immediately when released (high damping)

### Victory Conditions
- **All target words** must be formed completely
- **Exact spelling** required (no partial words like "PARTIE" for "PARTIES")
- **Correct spatial order** enforced

## 🐛 Known Issues & Solutions

### Common Problems
- **False victories**: Fixed by companion tile validation and spatial ordering
- **Stacked tile interference**: Resolved by Y-level grouping algorithm  
- **Performance on startup**: Optimized with delayed tile creation

## 🚀 Future Enhancements

- [ ] Apple Watch companion app
- [ ] More phrase categories (animals, food, movies)
- [ ] Difficulty levels (word length, time limits)
- [ ] Sound effects and haptic feedback
- [ ] Multiplayer support
- [ ] Achievement system

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`⌘+U` in Xcode)
4. Commit changes (`git commit -m 'Add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Code Style
- Follow Swift naming conventions
- Add unit tests for new algorithms
- Update `DEVELOPMENT_PROGRESS.md` for major features
- Use descriptive commit messages

## 📄 License

This project is open source. See individual file headers for specific licensing.

## 🎉 Acknowledgments

- Built with guidance from Claude Code AI assistant
- Inspired by classic word puzzle games
- Physics simulation powered by SpriteKit
- UI framework provided by SwiftUI

---

**Developed with ❤️ for iOS**