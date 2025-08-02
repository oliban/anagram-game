# Anagram Game - iOS Development Guide

## Project Overview
iOS multiplayer word game built with SwiftUI + SpriteKit. Players drag letter tiles to form words from scrambled sentences.

## 🚨 CORE WORKFLOW - ALWAYS FOLLOW
1. **Research First**: Start with `code_map.swift` - check freshness (`head -n 1`), search with `grep -n`, then read specific sections **IMPORTANT** If the file is older than 1 hour - run `python3 code_map_generator.py . --output code_map.swift` from project root.
2. **Plan**: Create detailed implementation plan, verify with me before coding
3. **Implement**: Write production-quality Swift code following all best practices
4. **Test**: Deploy with `build_and_test.sh` (includes server health checks), monitor logs, await my feedback
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
### Local Development
1. **Start Services**: `docker-compose -f docker-compose.services.yml up -d`
2. **Verify Health**: Check all service endpoints (3000, 3001, 3002, 3003)
3. **Version**: Increment `CFBundleVersion` and `CFBundleShortVersionString` in Info.plist
4. **Build iOS**: Clean build with local derived data (`-derivedDataPath ./build`)
5. **Deploy**: Install and launch on both simulators
6. **Verify**: Monitor Docker logs, check API calls, confirm connections

### Production Deployment (AWS)
**Detailed Guide**: See `docs/aws-production-server-management.md` for full AWS server management documentation.
- **Docker Build**: **CRITICAL** - Always build for linux/amd64 platform for ECS Fargate
- **Quick Health Check**: `curl -v http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com/api/status`

## ARCHITECTURE & ENVIRONMENT

### Microservices Architecture
**Client-Server**: iOS SwiftUI + SpriteKit ↔ Docker Services ↔ Shared PostgreSQL

**Services:**
- 🎮 **Game Server** (port 3000): Core multiplayer API + WebSocket
- 📊 **Web Dashboard** (port 3001): Monitoring interface
- 🔗 **Link Generator** (port 3002): Contribution link service
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

### iOS App Targets
- **Launch time**: < 3 seconds cold start
- **Memory usage**: < 100MB baseline, < 200MB peak
- **Frame rate**: 60fps animations, no dropped frames
- **Network**: API calls timeout after 10s, retry 3x with backoff
- **Battery**: Background processing < 5% battery drain/hour

### Backend Services
- **API response**: < 200ms average, < 500ms p95
- **Database queries**: < 50ms average, < 100ms complex queries
- **Uptime**: 99.9% availability target
- **Memory per service**: < 512MB under normal load
- **Docker startup**: < 30 seconds per service

### Monitoring Commands
```bash
# iOS performance check
instruments -t "Time Profiler" -D trace.trace YourApp.app

# Backend health check with timing
curl -w "@curl-format.txt" http://localhost:3000/api/status
```

## SECURITY REQUIREMENTS

### iOS Security
- **Keychain**: Store all sensitive data (tokens, passwords) in Keychain
- **Network**: HTTPS only, certificate pinning for production
- **Input validation**: Sanitize all user inputs before processing

### Backend Security
- **Input validation**: Validate all request parameters and body
- **SQL injection**: Use parameterized queries only
- **Rate limiting**: 100 requests/minute per IP on public endpoints
- **Secrets**: Environment variables only, never hardcoded
- **CORS**: Restrict origins to known clients only

### Security Checks
```bash
# Check for hardcoded secrets
grep -r "password\|secret\|key" --include="*.swift" --include="*.js" .

# Dependency vulnerability scan
npm audit
```

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

# Database (Microservices)
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# API Documentation
npm run docs  # Generate automated API docs at /api-docs endpoint

# Phrase Generation & Import
./server/scripts/generate-and-preview.sh "25-75:50" sv   # Generate Swedish phrases
node server/scripts/phrase-importer.js --input data/phrases-sv-*.json --import  # Import

# Shared Algorithm Testing
node -e "const alg = require('./shared/difficulty-algorithm'); console.log(alg.calculateScore({phrase: 'test phrase', language: 'en'}));"
```

### API Endpoints
- **Game Server (3000)**: `/api/status`, `/api/players`, `/api/phrases/for/:playerId`
- **Web Dashboard (3001)**: `/api/status`, `/api/monitoring/stats`
- **Link Generator (3002)**: `/api/status`
- **Admin Service (3003)**: `/api/status`, `/api/admin/phrases/batch-import`


### MCP Tools Available
- **iOS Simulator Control**: Screenshot, UI inspection, tap/swipe gestures, text input
- **IDE Integration**: Code diagnostics, error checking, code execution
- Use these tools for troubleshooting UI issues, testing interactions, and debugging

### Common Debugging
- **WebSocket issues**: Check server logs, verify NetworkManager.swift connections
- **Build failures**: Clean derived data, check Info.plist versions, verify simulator UUIDs
- **Database issues**: Test connection, verify schema, run server test suite
- **AWS ECS Platform Issues**: Always use `docker build --platform linux/amd64` for ECS Fargate

### Additional Resources
- **Device-User Association**: See `docs/device-user-association-guide.md`
- **AWS Production Management**: See `docs/aws-production-server-management.md`