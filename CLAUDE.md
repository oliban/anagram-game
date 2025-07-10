# Anagram Game - iOS Development Guide

## Project Overview
iOS multiplayer word game built with SwiftUI + SpriteKit. Players drag letter tiles to form words from scrambled sentences.

## 🚨 CORE WORKFLOW - ALWAYS FOLLOW
1. **Research First**: Start with `code_map.swift` - check freshness (`head -n 1`), search with `grep -n`, then read specific sections **IMPORTANT** If the file is older than 1 hour - run `python3 code_map_generator.py . --output code_map.swift` from project root.
2. **Plan**: Create detailed implementation plan, verify with me before coding
3. **Implement**: Write production-quality Swift code following all best practices
4. **Test**: Deploy to both simulators with `build_multi_sim.sh`, monitor server logs, await my feedback
5. **Never commit without explicit approval**

**When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."**

## CODE QUALITY REQUIREMENTS
- **Zero tolerance for bad patterns** - Stop and refactor immediately
- **No force unwrapping (!)** without safety checks
- **Proper memory management** - Use `weak self` in closures
- **SwiftUI best practices** - Correct `@State`, `@Binding`, `@ObservableObject` usage
- **Delete old code** when replacing - no migration functions or versioned names
- **Meaningful names** - `userIdentifier` not `id`
- **Guard statements** for early returns and unwrapping

**Recovery Protocol**: When interrupted by code quality issues, maintain awareness of your original task. After fixing patterns and ensuring quality, continue where you left off. Use todo list to track both the fix and your original task.

**Code is complete when**:
- ✅ Follows Swift/iOS best practices
- ✅ Uses proper memory management patterns
- ✅ Implements clean, readable logic
- ✅ Old code is deleted
- ✅ Swift documentation on public interfaces
- ✅ Handles errors gracefully

## EFFICIENT RESEARCH PROTOCOL
**Code Map First**: Always start with `code_map.swift` for all research
- Check freshness: `head -n 1 code_map.swift` (regenerate if > 1 hour old)
- Search targets: `grep -n "ClassName\|propertyName" code_map.swift`
- Use line numbers to read specific sections
- Only use Task agents for complex multi-file relationships

**Forbidden**: Broad searches (`grep -r`, `find`), reading entire files, multiple agents for simple lookups

## PROBLEM-SOLVING STRATEGIES
- **Use multiple agents** for parallel investigation of different codebase parts
- **Ultrathink** for complex architectural decisions
- **Reality checkpoints** after each feature, before major changes, when patterns feel wrong
- **Ask for guidance** when stuck: "I see approaches [A] vs [B]. Which do you prefer?"

## TESTING & DEPLOYMENT
**Multi-Simulator Testing**: Deploy to both iPhone 15 and iPhone 15 Pro simulators
- Build script: `/Users/fredriksafsten/Workprojects/anagram-game/build_multi_sim.sh`
- Monitor server logs: `tail -f server/server_output.log`
- Always await feedback before proceeding to next tasks

**Testing Strategy**:
- Complex game logic → XCTest unit tests first
- Simple UI components → Test after implementation
- Performance-critical paths → Add performance tests

## DEPLOYMENT SEQUENCE
1. **Server Setup**: Use safe server management (`./server/manage-server.sh restart`), monitor logs
2. **Version**: Increment `CFBundleVersion` and `CFBundleShortVersionString` in Info.plist
3. **Build**: Clean build with local derived data (`-derivedDataPath ./build`)
4. **Deploy**: Install and launch on both simulators
5. **Verify**: Monitor logs, check API calls, confirm connections

## ARCHITECTURE & ENVIRONMENT
**Client-Server**: iOS SwiftUI + SpriteKit ↔ WebSocket/REST ↔ Node.js + PostgreSQL
**Patterns**: MVVM with @Observable GameModel, Socket.IO for multiplayer, URLSession for HTTP
**Simulators**: iPhone 15 (`AF307F12-A657-4D6A-8123-240CBBEC5B31`), iPhone 15 Pro (`86355D8A-560E-465D-8FDC-3D037BCA482B`)
**Bundle ID**: `com.fredrik.anagramgame`

### Shared Algorithm Architecture
**Configuration-Based Scoring**: Both iOS and server read from `shared/difficulty-algorithm-config.json`
- **Server**: `shared/difficulty-algorithm.js` imports JSON config
- **iOS**: `SharedDifficultyConfig` struct in `NetworkManager.swift` reads same JSON
- **Benefits**: Single source of truth, no code duplication, easy maintenance
- **Performance**: Client-side scoring eliminates network calls during typing

## KEY PRINCIPLES
- **Clarity over cleverness** - Simple, obvious solutions preferred
- **Production quality only** - No shortcuts, no TODOs in final code
- **Feature branch** - No backwards compatibility needed
- **Measure first** - No premature optimization, use Instruments for real bottlenecks
- **Security minded** - Validate inputs, use Keychain for sensitive data

## WORKING MEMORY MANAGEMENT
- **When context gets long**: Re-read this CLAUDE.md file, summarize progress in PROGRESS.md, document current state before major changes
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

---

## REFERENCE COMMANDS

### Development
```bash
# Server Management (Safe, Port-Specific)
./server/manage-server.sh start    # Start server
./server/manage-server.sh stop     # Stop server safely
./server/manage-server.sh restart  # Restart server
./server/manage-server.sh status   # Check server status
./server/manage-server.sh logs     # View recent logs
tail -f server/server_output.log   # Live logs

# iOS Tests
xcodebuild test -project "Anagram Game.xcodeproj" -scheme "Anagram Game" -destination 'platform=iOS Simulator,name=iPhone 15'

# Database
node -e "require('./server/database/connection').testConnection()"
psql -d anagram_game -f server/database/schema.sql

# API Documentation
npm run docs  # Generate automated API docs at /api-docs endpoint

# Shared Algorithm Testing
node -e "const alg = require('./shared/difficulty-algorithm'); console.log(alg.calculateScore({phrase: 'test phrase', language: 'en'}));"
```

### API Endpoints
- `GET /api/status` - Server health check
- `POST /api/players` - Player registration (returns UUID)
- `GET /api/players/online` - Online player list
- `GET /api/phrases/for/:playerId` - Get targeted phrases
- `POST /api/phrases/create` - Create new phrase

### MCP Tools Available
- **iOS Simulator Control**: Screenshot, UI inspection, tap/swipe gestures, text input
- **IDE Integration**: Code diagnostics, error checking, code execution
- Use these tools for troubleshooting UI issues, testing interactions, and debugging

### Common Debugging
- **WebSocket issues**: Check server logs, verify NetworkManager.swift connections
- **Build failures**: Clean derived data, check Info.plist versions, verify simulator UUIDs
- **Database issues**: Test connection, verify schema, run server test suite
- **iOS Simulator issues**: Use MCP iOS Simulator tools for UI inspection, screenshots, and interaction testing