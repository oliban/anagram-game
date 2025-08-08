# Wordshelf - iOS Development Guide

## Project Overview
iOS multiplayer word game built with SwiftUI + SpriteKit. Players drag letter tiles to form words from scrambled sentences.

## 🚨 MANDATORY: iOS Simulator Debugging
**File-Based Logging**: Device-specific logs (`anagram-debug-iPhone-15.log`, `anagram-debug-iPhone-15-Pro.log`)
**Log Analysis Protocol**:
1. Run `./Scripts/tail-logs.sh` to identify most recent log file path
2. **CRITICAL**: Use device-specific logs (`anagram-debug-iPhone-15.log`) NOT old generic logs (`anagram-debug.log`)
3. Priority order: `iPhone-15.log` > `iPhone-15-Pro.log` > generic logs (avoid)
4. **YOU CAN READ iOS LOGS DIRECTLY**: Use `grep`, `head`, `tail` commands on the device-specific log file
5. Search patterns: `grep -E "(ENTERING_|GAME.*🎮|ERROR.*❌|USING_LOCAL)" /path/to/device-specific.log`
6. **ALWAYS CHECK iOS LOGS for debugging** - Don't rely only on server logs
**Code Usage**: `DebugLogger.shared.ui/network/error/info/game("message")` - Add to ALL new functions
**Categories**: 🎨 UI, 🌐 NETWORK, ℹ️ INFO, ❌ ERROR, 🎮 GAME
**🚨 CRITICAL DEBUG LOGGING RULE**: 
- **NEVER use `print()` for debug output** - it only goes to Xcode console, not to log files
- **ALWAYS use `DebugLogger.shared.method("message")`** - this writes to log files that you can read
- **Example**: `DebugLogger.shared.network("🔍 DEBUG: Variable = \(value)")` instead of `print("🔍 DEBUG: Variable = \(value)")`

## 🚨 CORE WORKFLOW - ALWAYS FOLLOW
1. **Research First**: Start with `code_map.swift` - check freshness (`head -n 1`), search with `grep -n`, then read specific sections **IMPORTANT** If the file is older than 1 hour - run `python3 code_map_generator.py . --output code_map.swift` from project root.
2. **Plan**: Create detailed implementation plan, verify with me before coding
3. **Implement**: Write production-quality Swift code following all best practices
4. **Test**: Deploy with `build_multi_sim.sh` (includes server health checks), await my feedback
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
# Main build script (includes server health checks)
./build_multi_sim.sh local             # Local development
./build_multi_sim.sh aws               # AWS production
./build_multi_sim.sh local --clean     # Clean build (AVOID - requires re-associating players)
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

### 🛡️ IMPLEMENTED SECURITY FEATURES (Phase 1 Complete)
- **✅ Environment Security**: Flexible dev/prod configuration with secure defaults
- **✅ CORS Hardening**: Restricted origins (`origin: true` in dev, domain whitelist in prod)
- **✅ Rate Limiting**: Realistic limits for word game usage patterns
  - Game Server: 120/30 requests per 15min (dev/prod) = ~8-2 per minute
  - Web Dashboard: 300/60 = ~20-4 per minute (dashboard polling)
  - Admin Service: 30/5 = ~2-0.3 per minute (strictest)
  - Link Generator: 60/15 general, 15/3 link creation
- **✅ Input Validation**: XSS/SQL injection protection with Joi + express-validator
  - Security patterns: `/^[a-zA-Z0-9\s\-_.,!?'"()åäöÅÄÖ]*$/` for safe text
  - UUID validation for IDs, language code validation
  - Sanitization for database inputs and output display

### 🔧 SECURITY CONFIGURATION
```bash
# Environment variables (automatically set in development):
SECURITY_RELAXED=true          # Enables relaxed CORS in development
LOG_SECURITY_EVENTS=true       # Logs CORS violations and security events
SKIP_RATE_LIMITS=false         # Rate limits active (set true to disable for testing)
ADMIN_API_KEY=test-admin-key-123 # For admin endpoint authentication (Phase 2)
```

### 🚨 SECURITY TESTING COMMANDS

#### Comprehensive Security Test Suite ✅ COMPLETE
```bash
# Run all security tests (recommended)
./security-testing/scripts/comprehensive-security-test.sh

# Test production security enforcement
./security-testing/scripts/production-security-test.sh

# Test WebSocket security specifically
node security-testing/scripts/test-websocket-security.js
```

#### Manual Security Testing
```bash
# Test rate limiting headers
curl -I http://localhost:3000/api/status
# Should show: RateLimit-Limit, RateLimit-Remaining, RateLimit-Reset

# Test XSS protection (should be blocked)
curl -X POST http://localhost:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "<script>alert(\"XSS\")</script>", "language": "en"}'

# Test SQL injection protection (should be blocked)  
curl -X POST http://localhost:3003/api/admin/phrases/batch-import \
  -H "Content-Type: application/json" \
  -d '{"phrases": [{"content": "SELECT * FROM users--"}]}'

# Monitor security events
docker-compose -f docker-compose.services.yml logs | grep -E "(🛡️|🔑|🚫|❌)"

# Test API authentication (should work with key)
curl -X POST http://localhost:3003/api/admin/phrases/batch-import \
  -H "Content-Type: application/json" \
  -H "X-API-Key: test-admin-key-123" \
  -d '{"phrases": [{"content": "valid phrase"}]}'
```

#### Production Security Testing (⚠️ Use with caution)
```bash
# Enable strict security mode temporarily
cp .env .env.backup
sed -i 's/SECURITY_RELAXED=true/SECURITY_RELAXED=false/' .env
docker-compose -f docker-compose.services.yml restart

# Run tests (should show rejections for unauthorized access)
node test-websocket-security.js

# Restore development mode
mv .env.backup .env
docker-compose -f docker-compose.services.yml restart
```

#### Security Monitoring
```bash
# Watch security events in real-time
docker-compose -f docker-compose.services.yml logs -f | grep -E "(🚫|❌|🔑|AUTH|CORS|🛡️)"

# Check service security configuration
docker-compose -f docker-compose.services.yml logs | grep -E "(🔧|🛡️|🔑|🔌)"
```

### 📋 REMAINING SECURITY TASKS (Phase 2)
- **iOS**: Keychain for sensitive data, HTTPS only, certificate pinning
- **Backend**: Admin API key authentication, WebSocket security
- **Monitoring**: Security event dashboards, failed auth tracking

### 🔍 SECURITY CHECKS
- `grep -r "password\|secret\|key"` for hardcoded secrets
- `npm audit` for vulnerabilities  
- Check rate limit headers in API responses
- Verify CORS configuration in server logs: `🔧 CORS Configuration` and `🛡️ Rate Limiting Configuration`

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
- **🚨 CRITICAL: If you use --clean flag, you MUST immediately re-associate logged-in players afterward!**
  - Clean builds reset device IDs, breaking auto-login for existing players
  - After clean build, run device association commands from `docs/device-user-association-guide.md`

---

## REFERENCE COMMANDS

### Development
```bash
# iOS Tests
xcodebuild test -project "Wordshelf.xcodeproj" -scheme "Wordshelf" -destination 'platform=iOS Simulator,name=iPhone 15'

# Database Access
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# Phrase Generation & Import
./server/scripts/generate-and-preview.sh "25-75:50" sv
node server/scripts/phrase-importer.js --input data/phrases-sv-*.json --import
```

### App Store Archive & Distribution
```bash
# Archive for App Store (requires Xcode 16+ with iOS 18 SDK)
xcodebuild clean archive \
  -project Wordshelf.xcodeproj \
  -scheme Wordshelf \
  -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Wordshelf.xcarchive \
  -sdk iphoneos18.5 \
  -configuration Release \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=5XR7USWXMZ \
  -allowProvisioningUpdates

# Export for App Store distribution
xcodebuild -exportArchive \
  -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Wordshelf.xcarchive \
  -exportPath ~/Desktop/WordshelfExport \
  -exportOptionsPlist ExportOptions.plist
```

**Important SDK Requirements:**
- Apple requires iOS 18 SDK or later for App Store submissions (as of 2024)
- Update SDK version in commands when Xcode updates (current: `iphoneos18.5`)
- Team ID: `5XR7USWXMZ` (configured in project settings)

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