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

### Build Script Usage (NEW)
**Enhanced workflow with automatic server health checking:**

```bash
# Recommended: Enhanced build with server health checks
./build_and_test.sh local              # Local development with health checks
./build_and_test.sh aws                # AWS production with health checks
./build_and_test.sh local --clean      # Clean build with health checks

# Direct build (legacy) - no server health checks
./build_multi_sim.sh local             # Local development only
./build_multi_sim.sh aws               # AWS production only
./build_multi_sim.sh local --clean     # Force clean build
```

**Enhanced Workflow**: Pre-build server health checks, auto-start services, AWS status validation, post-build verification.  
**Detailed Guide**: See `docs/aws-production-server-management.md` for full AWS server management documentation.

### Microservices Architecture (Local Development)
**All servers run as Docker containers with separate services:**

**Start all services for testing:**
```bash
docker-compose -f docker-compose.services.yml up -d
```

**Check service status:**
```bash
# View all running containers
docker-compose -f docker-compose.services.yml ps

# Test health endpoints
curl http://localhost:3000/api/status  # Game server
curl http://localhost:3001/api/status  # Web dashboard  
curl http://localhost:3002/api/status  # Link generator
```

**Monitor logs:**
```bash
# All services
docker-compose -f docker-compose.services.yml logs -f

# Specific service
docker-compose -f docker-compose.services.yml logs -f game-server
docker-compose -f docker-compose.services.yml logs -f web-dashboard
docker-compose -f docker-compose.services.yml logs -f link-generator
```

**Stop services:**
```bash
docker-compose -f docker-compose.services.yml down
```

**Testing Strategy**:
- Complex game logic → XCTest unit tests first
- Simple UI components → Test after implementation
- Performance-critical paths → Add performance tests

## DEPLOYMENT SEQUENCE
### Local Development (NEW)
1. **Start Services**: `docker-compose -f docker-compose.services.yml up -d`
2. **Verify Health**: Check all service endpoints (3000, 3001, 3002)
3. **Version**: Increment `CFBundleVersion` and `CFBundleShortVersionString` in Info.plist
4. **Build iOS**: Clean build with local derived data (`-derivedDataPath ./build`)
5. **Deploy**: Install and launch on both simulators
6. **Verify**: Monitor Docker logs, check API calls, confirm connections

### Production Deployment (AWS)
**For AWS production server management, see `docs/aws-production-server-management.md`**

1. **Infrastructure**: Use AWS CDK for ECS Fargate + Aurora Serverless v2
2. **Secrets**: Configure AWS Secrets Manager for environment variables  
3. **Docker Build**: **CRITICAL** - Always build for linux/amd64 platform for ECS Fargate
4. **Deploy**: GitHub Actions CI/CD pipeline to AWS
5. **Monitor**: CloudWatch logs and health checks

**Quick Health Check**: `curl -v http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com/api/status`

## ARCHITECTURE & ENVIRONMENT

### Microservices Architecture (NEW)
**Client-Server**: iOS SwiftUI + SpriteKit ↔ Docker Services ↔ Shared PostgreSQL

**Services:**
- 🎮 **Game Server** (port 3000): Core multiplayer API + WebSocket
- 📊 **Web Dashboard** (port 3001): Admin interface
- 🔗 **Link Generator** (port 3002): Contribution link service
- 🗄️ **PostgreSQL** (port 5432): Shared database

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

## BUILD WARNINGS
- **Never build the apps with clean flag if there is not a very good reason for it!**

---

## REFERENCE COMMANDS

### Development

#### Microservices (NEW - Primary Method)
```bash
# Start all services (game-server, web-dashboard, link-generator, postgres)
docker-compose -f docker-compose.services.yml up -d

# Stop all services
docker-compose -f docker-compose.services.yml down

# View logs (all services)
docker-compose -f docker-compose.services.yml logs -f

# View specific service logs
docker-compose -f docker-compose.services.yml logs -f game-server

# Rebuild services after code changes
docker-compose -f docker-compose.services.yml build
docker-compose -f docker-compose.services.yml up -d

# Check service health
curl http://localhost:3000/api/status  # Game server
curl http://localhost:3001/api/status  # Web dashboard
curl http://localhost:3002/api/status  # Link generator
```

#### Legacy Single Server (Deprecated)
```bash
# DEPRECATED - Use microservices above instead
./server/manage-server.sh start    # Start server
./server/manage-server.sh stop     # Stop server safely
./server/manage-server.sh restart  # Restart server
./server/manage-server.sh status   # Check server status
./server/manage-server.sh logs     # View recent logs
tail -f server/server_output.log   # Live logs
```

# iOS Tests
xcodebuild test -project "Anagram Game.xcodeproj" -scheme "Anagram Game" -destination 'platform=iOS Simulator,name=iPhone 15'

# Database (Microservices)
# Database runs in Docker container, accessible at localhost:5432
psql -h localhost -p 5432 -U postgres -d anagram_game
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# Database (Legacy)
node -e "require('./server/database/connection').testConnection()"
psql -d anagram_game -f server/database/schema.sql

# API Documentation
npm run docs  # Generate automated API docs at /api-docs endpoint

# Phrase Generation (AI-Powered with Clever Clues)
# Interactive workflow - generates phrases and shows immediate preview
./server/scripts/generate-and-preview.sh "0-50:15"      # 15 English phrases (easy)
./server/scripts/generate-and-preview.sh "0-50:15" sv   # 15 Swedish phrases (easy)
./server/scripts/generate-and-preview.sh "0-100:50" sv  # 50 Swedish phrases (easy-medium)
./server/scripts/generate-and-preview.sh "101-150:20"   # 20 English phrases (hard)

# Advanced multi-range generation
./server/scripts/generate-phrases.sh "0-50:100,51-100:100" --no-import  # Generate only
./server/scripts/generate-phrases.sh "200-250:25"                       # Generate and import

# Generated files use format: analyzed-{lang}-{range}-{count}-{timestamp}.json
# Example: analyzed-sv-0-100-50-2025-07-28T11-11-08.json

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
- **AWS ECS Platform Issues**: 
  - **Error**: `image Manifest does not contain descriptor matching platform 'linux/amd64'`
  - **Cause**: Docker image built for ARM architecture (Apple Silicon) instead of x86_64
  - **Solution**: Always use `docker build --platform linux/amd64` for ECS Fargate deployments
  - **Prevention**: Add platform flag to all Docker build commands in deployment scripts

### Device-User Association for Testing
When testing device-based authentication, you may need to associate existing users with specific simulators. See detailed guide: `docs/device-user-association-guide.md`

**Quick Summary**: Use debug logging to capture device IDs during registration attempts, then update the database to associate users with their intended devices.