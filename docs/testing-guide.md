# Wordshelf Testing Guide

## Overview
Comprehensive testing guide for the Wordshelf multiplayer word game, covering API testing, iOS app testing, WebSocket functionality, and system integration tests.

## Quick Test Commands

### 🚀 Essential Health Checks
```bash
# Check all services are running
docker-compose -f docker-compose.services.yml ps

# Test server health
curl -s http://192.168.1.188:3000/api/status | jq .

# Check player count
curl -s http://192.168.1.188:3000/api/players | jq '.players | length'

# Check rate limiting headers
curl -I http://192.168.1.188:3000/api/status 2>/dev/null | grep RateLimit

# Check CORS headers
curl -H "Origin: http://localhost:3001" -I http://192.168.1.188:3000/api/status 2>/dev/null | grep Access-Control
```

### 📱 iOS App Testing
```bash
# Build apps for testing
./build_multi_sim.sh local           # Local development
./build_multi_sim.sh aws            # AWS production
./build_multi_sim.sh local --clean  # Clean build (requires player re-association)

# Check iOS device logs
./Scripts/tail-logs.sh              # Find log file paths
grep -E "(ERROR|❌)" /path/to/device-specific.log | tail -20
grep -E "(NETWORK|🌐)" /path/to/device-specific.log | tail -20
```

## API Endpoint Testing

### Player Management
```bash
# Register a new player
curl -X POST http://192.168.1.188:3000/api/players/register \
  -H "Content-Type: application/json" \
  -d '{"name": "TestPlayer", "language": "en"}' | jq .

# Get online players
curl -s http://192.168.1.188:3000/api/players | jq '.players[] | {name: .name, id: .id}'

# Get player stats
curl -s http://192.168.1.188:3000/api/players/{playerId}/stats | jq .

# Get leaderboard
curl -s http://192.168.1.188:3000/api/leaderboard/legends | jq '.players[].name'
```

### Phrase Operations
```bash
# Create a custom phrase (all words must be ≤7 characters)
curl -X POST http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{
    "content": "test phrase",
    "language": "en",
    "senderId": "YOUR_PLAYER_ID",
    "targetId": "TARGET_PLAYER_ID",
    "hint": "a test"
  }' | jq '.phrase | {id: .id, content: .content, senderName: .senderName}'

# Get phrases for player
curl -s http://192.168.1.188:3000/api/phrases/for/{playerId} | jq '.phrases | length'

# Complete a phrase
curl -X POST http://192.168.1.188:3000/api/phrases/{phraseId}/complete \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "YOUR_PLAYER_ID",
    "hintsUsed": 0,
    "completionTime": 5000
  }' | jq .

# Skip a phrase
curl -X POST http://192.168.1.188:3000/api/phrases/{phraseId}/skip \
  -H "Content-Type: application/json" \
  -d '{"playerId": "YOUR_PLAYER_ID"}' | jq .
```

### Configuration & Monitoring
```bash
# Get level configuration
curl -s http://192.168.1.188:3000/api/config/levels | jq '.config.skillLevels | length'

# Get monitoring stats (web dashboard)
curl -s http://192.168.1.188:3001/api/monitoring/stats | jq .

# Check phrase inventory
curl -s http://192.168.1.188:3001/api/monitoring/stats | jq '.phraseInventory'
```

## Database Testing

### Direct Database Queries
```bash
# Access database
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game

# Common queries
SELECT COUNT(*) FROM players WHERE is_online = true;
SELECT COUNT(*) FROM phrases WHERE is_global = true;
SELECT * FROM players ORDER BY created_at DESC LIMIT 5;
SELECT content, hint, difficulty_level FROM phrases WHERE created_by_player_id IS NOT NULL LIMIT 10;
```

### Database Health Checks
```bash
# Check connection pool
docker-compose -f docker-compose.services.yml logs game-server | grep "DATABASE: Client" | tail -10

# Check for database errors
docker-compose -f docker-compose.services.yml logs | grep -E "(ERROR.*database|failed to connect|pool.*error)"
```

## WebSocket Testing

### Manual WebSocket Testing with wscat
```bash
# Install wscat if needed
npm install -g wscat

# Connect to WebSocket
wscat -c ws://192.168.1.188:3000

# After connecting, send:
{"type": "register", "playerId": "YOUR_PLAYER_ID"}

# Listen for events:
# - player-joined
# - player-left
# - new-phrase
# - phrase-completed
```

### Automated WebSocket Test
```javascript
// Save as test-websocket.js
const io = require('socket.io-client');
const socket = io('http://192.168.1.188:3000');

socket.on('connect', () => {
    console.log('✅ Connected to WebSocket');
    socket.emit('register', { playerId: 'test-player-id' });
});

socket.on('new-phrase', (data) => {
    console.log('📨 New phrase received:', data);
});

socket.on('player-list-updated', (data) => {
    console.log('👥 Player list updated:', data.players.length, 'players online');
});

// Run with: node test-websocket.js
```

## Security Testing

### Rate Limiting Test
```bash
# Rapid-fire requests to test rate limiting
for i in {1..50}; do 
    curl -s -o /dev/null -w "%{http_code}\n" http://192.168.1.188:3000/api/status
done | sort | uniq -c

# Expected: Should see 429 (Too Many Requests) after limit
```

### Input Validation Test
```bash
# Test XSS prevention
curl -X POST http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "<script>alert(\"XSS\")</script>", "language": "en"}'

# Test SQL injection prevention  
curl -X POST http://192.168.1.188:3000/api/players/register \
  -H "Content-Type: application/json" \
  -d '{"name": "test\"; DROP TABLE players; --", "language": "en"}'

# Test word length validation (max 7 chars per word)
curl -X POST http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "verylongword test", "language": "en"}'
```

### Comprehensive Security Test
```bash
# Run full security test suite
./security-testing/scripts/comprehensive-security-test.sh

# Test production security
./security-testing/scripts/production-security-test.sh
```

## Performance Testing

### Load Testing
```bash
# Simple concurrent request test
for i in {1..10}; do
    (curl -s http://192.168.1.188:3000/api/status > /dev/null && echo "Request $i: Success") &
done
wait

# Measure response times
for i in {1..5}; do
    curl -s -o /dev/null -w "Request $i: %{time_total}s\n" http://192.168.1.188:3000/api/status
done
```

### Memory & Resource Monitoring
```bash
# Check Docker container stats
docker stats --no-stream

# Check specific service memory
docker-compose -f docker-compose.services.yml exec game-server ps aux

# Monitor logs for memory issues
docker-compose -f docker-compose.services.yml logs | grep -i "memory\|heap\|oom"
```

## Integration Testing

### End-to-End Game Flow Test
```bash
# 1. Register two players
PLAYER1_ID=$(curl -s -X POST http://192.168.1.188:3000/api/players/register \
  -H "Content-Type: application/json" \
  -d '{"name": "Player1", "language": "en"}' | jq -r '.player.id')

PLAYER2_ID=$(curl -s -X POST http://192.168.1.188:3000/api/players/register \
  -H "Content-Type: application/json" \
  -d '{"name": "Player2", "language": "en"}' | jq -r '.player.id')

# 2. Player1 sends phrase to Player2
PHRASE_ID=$(curl -s -X POST http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d "{
    \"content\": \"hello world\",
    \"language\": \"en\",
    \"senderId\": \"$PLAYER1_ID\",
    \"targetId\": \"$PLAYER2_ID\",
    \"hint\": \"greeting\"
  }" | jq -r '.phrase.id')

# 3. Player2 fetches phrases
curl -s http://192.168.1.188:3000/api/phrases/for/$PLAYER2_ID | jq '.phrases[0] | {content: .content, senderName: .senderName}'

# 4. Player2 completes phrase
curl -X POST http://192.168.1.188:3000/api/phrases/$PHRASE_ID/complete \
  -H "Content-Type: application/json" \
  -d "{
    \"playerId\": \"$PLAYER2_ID\",
    \"hintsUsed\": 0,
    \"completionTime\": 10000
  }" | jq '.completion'
```

### Emoji Collection Test
```bash
# Check player's emoji collection
curl -s http://192.168.1.188:3000/api/players/{playerId}/stats | jq '.rarestEmojis'

# Complete phrase with emoji celebration
curl -X POST http://192.168.1.188:3000/api/phrases/{phraseId}/complete \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "YOUR_PLAYER_ID",
    "hintsUsed": 0,
    "completionTime": 5000,
    "celebrationEmojis": []
  }' | jq '.emojiCollection'
```

## Troubleshooting Common Issues

### Issue: "Unknown Player" in notifications
```bash
# Check if sender lookup is working
curl -s http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "test ok", "language": "en", "senderId": "VALID_ID", "targetId": "VALID_ID", "hint": "test"}' \
  | jq '.phrase.senderName'
# Should return actual player name, not "Unknown Player"
```

### Issue: Rate limiting blocking legitimate requests
```bash
# Check rate limit configuration
docker-compose -f docker-compose.services.yml exec game-server env | grep SKIP_RATE

# Temporarily disable rate limits for testing
# Add to docker-compose.services.yml: SKIP_RATE_LIMITS=true
```

### Issue: Phrases not appearing in iOS app
```bash
# Check WebSocket connection
docker-compose -f docker-compose.services.yml logs game-server | grep -E "(Socket|WebSocket|new-phrase)"

# Check iOS logs for WebSocket events
grep "SOCKET\|WebSocket" /path/to/device-specific.log | tail -20
```

### Issue: Docker containers not updating
```bash
# Force rebuild without cache
docker-compose -f docker-compose.services.yml down
docker-compose -f docker-compose.services.yml build --no-cache
docker-compose -f docker-compose.services.yml up -d

# Verify latest code is deployed
docker-compose -f docker-compose.services.yml exec game-server cat package.json | grep version
```

## Automated Test Suites

### Run All Server Tests
```bash
cd server
./run_tests.sh

# Or specific test suites
node test_api_suite.js
node test_comprehensive_suite.js
node test_websocket_data_structure.js
```

### iOS Testing (Manual)
1. Build apps: `./build_multi_sim.sh local`
2. Register players on both simulators
3. Send phrases between simulators
4. Check iOS logs: `grep "ERROR\|❌" /path/to/log`
5. Verify WebSocket notifications appear

## Monitoring & Logging

### Real-time Log Monitoring
```bash
# All services
docker-compose -f docker-compose.services.yml logs -f

# Specific service
docker-compose -f docker-compose.services.yml logs -f game-server

# Filter for errors
docker-compose -f docker-compose.services.yml logs -f | grep -E "(ERROR|❌|FAIL|Exception)"

# iOS app logs
tail -f /path/to/device-specific.log | grep -E "(ERROR|NETWORK|GAME)"
```

### Health Dashboard
```bash
# Open in browser
open http://192.168.1.188:3001

# API status
curl -s http://192.168.1.188:3001/api/monitoring/stats | jq '.onlinePlayers, .activePhrases, .completionRate'
```

## Testing Checklist

### Before Release
- [ ] All API endpoints return expected data
- [ ] WebSocket notifications working between players
- [ ] Rate limiting active but not blocking normal usage
- [ ] Security headers present (CORS, rate limit)
- [ ] Database queries performant (<50ms)
- [ ] iOS apps can register and play
- [ ] Phrase sender names display correctly
- [ ] Emoji collections show all rarities
- [ ] No memory leaks after extended play
- [ ] Error messages user-friendly

### After Updates
- [ ] Docker containers rebuilt and deployed
- [ ] Database migrations applied if needed
- [ ] iOS apps rebuilt if client changes made
- [ ] Integration tests pass
- [ ] No new errors in logs
- [ ] Performance metrics unchanged or improved

## Useful Debug Commands

```bash
# Find player IDs for testing
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "SELECT id, name FROM players WHERE is_online = true;"

# Clear test data
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "DELETE FROM phrases WHERE content LIKE 'test%';"

# Check phrase validation rules
curl -X POST http://192.168.1.188:3000/api/phrases/create \
  -H "Content-Type: application/json" \
  -d '{"content": "YOUR_TEST_PHRASE", "language": "en"}' 2>&1 | jq '.error'

# Monitor WebSocket events in real-time
docker-compose -f docker-compose.services.yml logs -f game-server | grep -E "(emit|on\()"
```

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Health check | `curl -s http://192.168.1.188:3000/api/status \| jq .status` |
| Player count | `curl -s http://192.168.1.188:3000/api/players \| jq '.players \| length'` |
| Create phrase | `curl -X POST .../api/phrases/create -d '{"content":"test", "language":"en", ...}'` |
| View logs | `docker-compose -f docker-compose.services.yml logs -f game-server` |
| iOS logs | `./Scripts/tail-logs.sh` then `grep ERROR /path/to/log` |
| Rebuild | `docker-compose -f docker-compose.services.yml down && ... up -d --build` |
| Database | `docker-compose ... exec postgres psql -U postgres -d anagram_game` |

---

Last updated: 2025-08-09