# Anagram Game - iOS Development Guide

## Project Overview
iOS multiplayer word game built with SwiftUI + SpriteKit. Players drag letter tiles to form words from scrambled sentences.

## 🚨 MANDATORY: iOS Simulator Debugging
**File-Based Logging**: Device-specific logs (`anagram-debug-iPhone-15.log`, `anagram-debug-iPhone-15-Pro.log`)
**Log Analysis Protocol**:
1. Run `./Scripts/tail-logs.sh` to identify most recent log file path
2. **CRITICAL**: Use device-specific logs (`anagram-debug-iPhone-15.log`) NOT old generic logs (`anagram-debug.log`)
3. Priority order: `iPhone-15.log` > `iPhone-15-Pro.log` > generic logs (avoid)
4. Use `grep`, `head`, `tail` commands on the device-specific log file
5. Search patterns: `grep -E "(ENTERING_|GAME.*🎮|ERROR.*❌|USING_LOCAL)" /path/to/device-specific.log`
**Code Usage**: `DebugLogger.shared.ui/network/error/info/game("message")` - Add to ALL new functions
**Categories**: 🎨 UI, 🌐 NETWORK, ℹ️ INFO, ❌ ERROR, 🎮 GAME

## 🚨 CORE WORKFLOW - ALWAYS FOLLOW
1. **Research First**: Start with `code_map.swift` - check freshness (`head -n 1`), search with `grep -n`, then read specific sections **IMPORTANT** If the file is older than 1 hour - run `python3 code_map_generator.py . --output code_map.swift` from project root.
2. **Plan**: Create detailed implementation plan, verify with me before coding
3. **Implement**: Write production-quality Swift code following all best practices
4. **Test**: Deploy with `build_and_test.sh` (includes server health checks), await my feedback
5. **Commit when requested** - "commit and push" is explicit approval

**When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."**

## DEPLOYMENT GUIDELINES
- Always build new apps using the build script and wait for feedback before proceeding
- When user says "commit and push", that constitutes explicit approval to commit
- **🚨 LOG MONITORING: For debugging, use device-specific logs via `./Scripts/tail-logs.sh` to find path, then `grep`/`head`/`tail` on specific device log files. Do NOT use tail in blocking mode.**

## CODE QUALITY REQUIREMENTS
- **Zero tolerance for bad patterns** - Stop and refactor immediately
- **No force unwrapping (!)** without safety checks
- **Proper memory management** - Use `weak self` in closures
- **SwiftUI best practices** - Correct `@State`, `@Binding`, `@ObservableObject` usage
- **Delete old code** when replacing - no migration functions or versioned names
- **NO FALLBACKS** - Never keep old code as fallback when rewriting functions
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
- ✅ **Includes appropriate DebugLogger.shared logging statements**

## SWIFT-SPECIFIC GUIDELINES
- **Async/await over callbacks**: `func fetchUser() async throws -> User`
- **@Observable over ObservableObject**: Use Swift 5.9+ observation framework
- **Capture lists required**: `{ [weak self] in self?.method() }` prevents retain cycles
- **Task lifecycle**: Use `.task { await loadData() }` for auto-cancellation
- **View composition**: Extract complex views into smaller components
- **State ownership**: Keep @State private, pass down as @Binding
- **Environment over singletons**: Use @Environment for shared state

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

### ⚠️ IMPORTANT: Docker Network Access
**NEVER use localhost curl commands** - This is a legacy pattern that doesn't work with Docker containers.
- ❌ WRONG: `curl http://localhost:3000/api/status`
- ✅ CORRECT: `docker-compose -f docker-compose.services.yml exec game-server wget -q -O - http://localhost:3000/api/status`
- ✅ CORRECT: Use Docker exec to run commands inside containers
- ✅ CORRECT: Test from iOS simulators which connect via host network

### Build Script Usage
```bash
# Recommended: Enhanced build with server health checks
./build_and_test.sh local              # Local development with health checks
./build_and_test.sh aws                # AWS production with health checks
./build_and_test.sh local --clean      # Clean build with health checks

# Direct build (no server health checks)
./build_multi_sim.sh local             # Local development only
./build_multi_sim.sh aws               # AWS production only
```

### Microservices Architecture (Local Development)
**Docker Services Management:**
```bash
# Start/stop all services
docker-compose -f docker-compose.services.yml up -d
docker-compose -f docker-compose.services.yml down

# View logs
docker-compose -f docker-compose.services.yml logs -f
docker-compose -f docker-compose.services.yml logs -f [service-name]

# Health checks (inside containers)
docker-compose -f docker-compose.services.yml exec [service] wget -q -O - http://localhost:[port]/api/status
```

**Testing Strategy**:
- Complex game logic → XCTest unit tests first
- Simple UI components → Test after implementation
- Performance-critical paths → Add performance tests

## DEPLOYMENT SEQUENCE
### Local: Start services → Verify health → Update version → Build iOS → Deploy → Monitor
### AWS: Build linux/amd64 → Deploy → Health check (see `docs/aws-production-server-management.md`)

## ARCHITECTURE & ENVIRONMENT

### Microservices Architecture
**Client-Server**: iOS SwiftUI + SpriteKit ↔ Docker Services ↔ Shared PostgreSQL

**Services:**
- 🎮 **Game Server** (port 3000): Core multiplayer API + WebSocket
- 📊 **Web Dashboard** (port 3001): Monitoring interface
- 🔗 **Link Generator** (port 3002): Contribution link service + phrase creation web interface
- 🔧 **Admin Service** (port 3003): Content management & batch operations
- 🗄️ **PostgreSQL** (port 5432): Shared database

**Patterns**: MVVM with @Observable GameModel, Socket.IO for multiplayer, URLSession for HTTP
**Simulators**: iPhone 15 (`AF307F12-A657-4D6A-8123-240CBBEC5B31`), iPhone 15 Pro (`86355D8A-560E-465D-8FDC-3D037BCA482B`)
**Bundle ID**: `com.fredrik.anagramgame`

### Shared Algorithm Architecture
**Configuration-Based Scoring**: Both iOS and server read from `shared/difficulty-algorithm-config.json`
- Single source of truth, no code duplication
- Client-side scoring eliminates network calls during typing

## PERFORMANCE STANDARDS
- **iOS**: Launch <3s, Memory <100MB baseline, 60fps animations, API timeout 10s
- **Backend**: API <200ms avg, DB queries <50ms, 99.9% uptime, Memory <512MB/service
- **Monitoring**: Use Instruments for iOS, `curl -w` for API timing

## SECURITY REQUIREMENTS
- **iOS**: Keychain for sensitive data, HTTPS only, input validation, certificate pinning
- **Backend**: Parameterized queries, rate limiting (100/min), env vars for secrets, CORS restrictions
- **Checks**: `grep -r "password\|secret\|key"` for hardcoded secrets, `npm audit` for vulnerabilities

## KEY PRINCIPLES
- **NO LEGACY** - Always remove old code when building replacements
- **Clarity over cleverness** - Simple, obvious solutions preferred
- **Production quality only** - No shortcuts, no TODOs in final code
- **Feature branch** - No backwards compatibility needed
- **Measure first** - No premature optimization, use Instruments for real bottlenecks
- **Security minded** - Validate inputs, use Keychain for sensitive data

## WORKING MEMORY MANAGEMENT
- **When context gets long**: Re-read this CLAUDE.md file, summarize progress in PROGRESS.md, document current state before major changes
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

## BUILD WARNINGS
- **Never build the apps with clean flag if there is not a very good reason for it!**

---

## REFERENCE COMMANDS

### Development
```bash
# iOS Tests
xcodebuild test -project "Anagram Game.xcodeproj" -scheme "Anagram Game" -destination 'platform=iOS Simulator,name=iPhone 15'

# Database Access
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# Phrase Generation & Import
./server/scripts/generate-and-preview.sh "25-75:50" sv
node server/scripts/phrase-importer.js --input data/phrases-sv-*.json --import
```

### API Endpoints
- **Game Server (3000)**: `/api/status`, `/api/players`, `/api/phrases/for/:playerId`, `/api/phrases/create`
- **Web Dashboard (3001)**: `/api/status`, `/api/monitoring/stats`
- **Link Generator (3002)**: `/api/status`, `/contribute/:token`, `/api/contribution/:token`
- **Admin Service (3003)**: `/api/status`, `/api/admin/phrases/batch-import`



### Common Debugging
- **WebSocket**: Check server logs, verify NetworkManager.swift connections
- **Build failures**: Clean derived data, check Info.plist versions
- **AWS ECS**: Always use `docker build --platform linux/amd64`
- **MCP Tools**: iOS Simulator control, IDE diagnostics available
- **Docs**: `docs/device-user-association-guide.md`, `docs/aws-production-server-management.md`