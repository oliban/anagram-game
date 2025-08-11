# Reference Commands

## Development Commands

### iOS Testing
```bash
# Run iOS unit tests
xcodebuild test -project "Wordshelf.xcodeproj" -scheme "Wordshelf" -destination 'platform=iOS Simulator,name=iPhone 15'

# Build for different environments
./build_multi_sim.sh local             # Local development 
./build_multi_sim.sh staging           # Pi staging server
./build_multi_sim.sh aws               # AWS production
./build_multi_sim.sh [mode] --clean    # Clean build (AVOID - requires re-associating players)
```

### Database Access
```bash
# Connect to PostgreSQL database
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# Common database queries
SELECT COUNT(*) FROM players WHERE is_online = true;
SELECT COUNT(*) FROM phrases WHERE is_global = true;
SELECT * FROM players ORDER BY created_at DESC LIMIT 5;
SELECT content, hint, difficulty_level FROM phrases WHERE created_by_player_id IS NOT NULL LIMIT 10;
```

### Docker Services Management
```bash
# Start/stop all services
docker-compose -f docker-compose.services.yml up -d
docker-compose -f docker-compose.services.yml down

# View logs
docker-compose -f docker-compose.services.yml logs -f
docker-compose -f docker-compose.services.yml logs -f [service-name]

# Health checks (inside containers)
docker-compose -f docker-compose.services.yml exec [service] wget -q -O - http://localhost:[port]/api/status

# Force recreate containers
docker-compose -f docker-compose.services.yml up -d --force-recreate

# Clean Docker system
docker system prune -a
```

## App Store Archive & Distribution

### Archive Commands
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

### SDK Requirements
- **Apple requires iOS 18 SDK** or later for App Store submissions (as of 2024)
- **Update SDK version** in commands when Xcode updates (current: `iphoneos18.5`)
- **Team ID**: `5XR7USWXMZ` (configured in project settings)

### Release Script
```bash
# App Store Release Archive (creates signed .xcarchive)
./scripts/archive-for-release.sh
```

## API Endpoints

### Game Server (Port 3000)

#### Core API
- **`/api/status`** - Health check
- **`/api/players`** - Player management
- **`/api/players/register`** - Register new player
- **`/api/players/{playerId}/stats`** - Get player statistics
- **`/api/phrases/for/{playerId}`** - Get phrases for player
- **`/api/phrases/create`** - Create new phrase
- **`/api/phrases/{phraseId}/complete`** - Complete phrase
- **`/api/phrases/{phraseId}/skip`** - Skip phrase
- **`/api/leaderboard/legends`** - Get leaderboard
- **`/api/config/levels`** - Get level configuration

#### Contribution System (Consolidated)
- **`/contribute/{token}`** - Web contribution page
- **`/api/contribution/request`** - Generate contribution link
- **`/api/contribution/{token}`** - Get link details
- **`/api/contribution/{token}/submit`** - Submit contributed phrase
- **`/api/contribution/status`** - Contribution system health

### Web Dashboard (Port 3001)
- **`/api/status`** - Health check
- **`/api/monitoring/stats`** - Real-time statistics

### Phrase Import System (Security Update)
- **REMOVED**: Admin Service and all HTTP-based bulk import endpoints
- **REPLACEMENT**: Direct database script access only
  - `node scripts/phrase-importer.js --input file.json --import`
  - **Security**: No HTTP exposure, direct database access only

## Testing Commands

### API Testing
```bash
# Health check
curl -s http://localhost:3000/api/status | jq .

# Register player
curl -X POST http://localhost:3000/api/players/register \
  -H "Content-Type: application/json" \
  -d '{"name": "TestPlayer", "language": "en"}' | jq .

# Get players
curl -s http://localhost:3000/api/players | jq '.players | length'

# Create phrase
curl -X POST http://localhost:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{
    "content": "test phrase",
    "language": "en",
    "senderId": "PLAYER_ID",
    "targetId": "TARGET_ID",
    "hint": "a test"
  }' | jq .
```

### Security Testing
```bash
# Test rate limiting
curl -I http://localhost:3000/api/status
# Should show: RateLimit-Limit, RateLimit-Remaining, RateLimit-Reset

# Test XSS protection (should be blocked)
curl -X POST http://localhost:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "<script>alert(\"XSS\")</script>", "language": "en"}'

# Run security test suite
./security-testing/scripts/comprehensive-security-test.sh
```

### Automated Testing
```bash
# Run full automated test suite (recommended)
node testing/scripts/automated-test-runner.js

# Quick validation during development
SKIP_PERFORMANCE=true node testing/scripts/automated-test-runner.js

# Individual test suites
node testing/api/test_updated_simple.js                    # Core API tests
node testing/integration/test_socketio_realtime.js         # WebSocket/multiplayer
node testing/integration/test_user_workflows.js            # End-to-end workflows
node testing/performance/test_performance_suite.js         # Load testing
```

## Monitoring & Debugging

### Service Health
```bash
# Check service status
curl http://localhost:3000/api/status
curl http://localhost:3001/api/status

# Monitor Docker stats
docker stats --no-stream

# Check specific service memory
docker-compose -f docker-compose.services.yml exec game-server ps aux
```

### Log Analysis
```bash
# View all service logs
docker-compose -f docker-compose.services.yml logs -f

# Filter for errors
docker-compose -f docker-compose.services.yml logs -f | grep -E "(ERROR|❌|FAIL|Exception)"

# iOS app logs
./Scripts/tail-logs.sh              # Find log file paths
grep -E "(ERROR|❌)" /path/to/device-specific.log | tail -20
grep -E "(NETWORK|🌐)" /path/to/device-specific.log | tail -20

# Security events
docker-compose -f docker-compose.services.yml logs -f | grep -E "(🚫|❌|🔑|AUTH|CORS|🛡️)"
```

### Performance Monitoring
```bash
# API response times
curl -s -o /dev/null -w "Response time: %{time_total}s\n" http://localhost:3000/api/status

# Memory usage
docker-compose -f docker-compose.services.yml logs | grep -i "memory\|heap\|oom"

# Database performance
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "SELECT * FROM pg_stat_activity;"
```

## Utility Commands

### Data Management
```bash
# Find player IDs for testing
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "SELECT id, name FROM players WHERE is_online = true;"

# Clear test data
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "DELETE FROM phrases WHERE content LIKE 'test%';"

# Backup database
docker-compose -f docker-compose.services.yml exec postgres pg_dump -U postgres anagram_game > backup.sql
```

### Network & Connectivity
```bash
# Test WebSocket connection
wscat -c ws://localhost:3000

# Check port availability
netstat -an | grep :3000
netstat -an | grep :3001

# Test from inside Docker containers
docker-compose -f docker-compose.services.yml exec game-server wget -q -O - http://localhost:3000/api/status
```

## Environment-Specific Commands

### Local Development
```bash
# Start local environment
docker-compose -f docker-compose.services.yml up -d
./build_multi_sim.sh local

# Service URLs
# Game Server: http://192.168.1.188:3000
# Web Dashboard: http://192.168.1.188:3001
```

### Pi Staging
```bash
# Deploy to staging
./scripts/deploy-staging.sh

# Manual staging operations
ssh pi@192.168.1.222
cat ~/cloudflare-tunnel-url.txt
sudo systemctl restart cloudflare-tunnel
```

### AWS Production
```bash
# Deploy to AWS
./build_multi_sim.sh aws

# AWS-specific Docker build
docker build --platform linux/amd64 .
```

## Quick Reference

### Essential Health Checks
| Check | Command |
|-------|---------|
| API Status | `curl -s http://localhost:3000/api/status \| jq .status` |
| Player Count | `curl -s http://localhost:3000/api/players \| jq '.players \| length'` |
| Service Logs | `docker-compose -f docker-compose.services.yml logs -f game-server` |
| iOS Logs | `./Scripts/tail-logs.sh` then `grep ERROR /path/to/log` |
| Database | `docker-compose ... exec postgres psql -U postgres -d anagram_game` |
| Container Stats | `docker stats --no-stream` |

### Common Debugging Patterns
| Issue | Command |
|-------|---------|
| WebSocket Problems | Check server logs, verify NetworkManager.swift connections |
| Build Failures | Clean derived data, check Info.plist versions |
| Database Issues | Check connection pool, verify queries |
| Performance | Use Instruments for iOS, monitor Docker stats |
| Security | Check rate limit headers, verify CORS configuration |

### File Locations
| Purpose | Path |
|---------|------|
| iOS Logs | Device-specific: `anagram-debug-iPhone-15.log` |
| Database Files | `server/data/` directory |
| Configuration | `shared/difficulty-algorithm-config.json` |
| Docker Compose | `docker-compose.services.yml` |
| Build Scripts | `./build_multi_sim.sh`, `./scripts/` |

## Documentation Links

### Internal Documentation
- **GitFlow Workflow**: `docs/IMPROVED_WORKFLOW_GUIDE.md` - Complete guide to new branch-based workflow
- **Workflow Comparison**: `docs/WORKFLOW_COMPARISON.md` - Current vs improved workflow benefits
- **CI/CD Execution**: `testing/docs/CI_CD_EXECUTION_GUIDE.md` - When and how tests run
- **Testing Strategy**: `testing/docs/TESTING_STRATEGY.md` - Complete testing approach
- **Device Association**: `docs/device-user-association-guide.md` - Player re-association after clean builds
- **AWS Management**: `docs/aws-production-server-management.md` - Production server management

### Setup & Configuration
- **GitFlow Setup**: `./scripts/setup-gitflow.sh` - One-command GitFlow initialization
- **Archive Script**: `./scripts/archive-for-release.sh` - App Store release preparation

### System Information
- **Simulators**: iPhone 15 (`AF307F12-A657-4D6A-8123-240CBBEC5B31`), iPhone 15 Pro (`86355D8A-560E-465D-8FDC-3D037BCA482B`)
- **Bundle ID**: `com.fredrik.anagramgame`
- **Patterns**: MVVM with @Observable GameModel, Socket.IO for multiplayer, URLSession for HTTP