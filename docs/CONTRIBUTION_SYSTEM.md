# 🔗 Contribution System Documentation

## Overview

The Wordshelf contribution system allows players to share custom phrase puzzles with friends via shareable links. Contributors can submit phrases through a web interface, and they are automatically delivered to specific players.

## Architecture (Post-Consolidation)

As of August 2025, the contribution system has been **consolidated into the Game Server** for simplified architecture and better Cloudflare tunnel compatibility.

### Service Integration
- **Previously**: Standalone link-generator service (port 3002)
- **Currently**: Integrated into game-server (port 3000) at `/api/contribution/*` endpoints

## How It Works

### 1. Link Generation
Players can generate contribution links in the iOS app:

```swift
// iOS: PlayerService.swift
func generateContributionLink() async throws -> String {
    let url = "\(AppConfig.contributionAPIURL)"
    // Returns: https://tunnel-url.trycloudflare.com/api/contribution/request
}
```

### 2. Token System
Each contribution link contains a unique token that:
- Identifies the requesting player
- Has a configurable expiration period
- Tracks usage statistics
- Ensures security and prevents abuse

### 3. Web Interface
Contributors access a user-friendly web form at:
```
https://tunnel-url.trycloudflare.com/contribute/{token}
```

The form includes:
- Phrase input field (the scrambled sentence)
- Clue/hint input field (optional)
- Contributor name field (optional)
- Language selection
- Real-time validation

### 4. Phrase Delivery
When a contributor submits a phrase:
1. **Validation**: Input is sanitized and validated
2. **Database**: Phrase stored with enhanced metadata
3. **WebSocket**: Real-time notification sent to requesting player
4. **Difficulty**: Automatic difficulty calculation applied

## API Endpoints

### Game Server Integration (`/api/contribution/*`)

#### Request Contribution Link
```http
POST /api/contribution/request
Content-Type: application/json

{
  "playerId": "uuid",
  "expirationHours": 24
}
```

#### Submit Contribution
```http
POST /api/contribution/submit
Content-Type: application/json

{
  "token": "contribution-token",
  "phrase": "example scrambled sentence",
  "clue": "optional hint",
  "contributorName": "Anonymous",
  "language": "en"
}
```

#### Web Interface
```http
GET /contribute/{token}
```
Returns HTML form for contribution submission.

## Database Schema

### Contribution Tokens
```sql
CREATE TABLE contribution_tokens (
    id UUID PRIMARY KEY,
    token VARCHAR(255) UNIQUE NOT NULL,
    requesting_player_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);
```

### Enhanced Phrases
Contributed phrases use the existing `phrases` table with:
- `phrase_type: 'custom'`
- `sender_id: null` (system-generated)
- `target_ids: [requesting_player_id]`
- `is_global: false`
- `contributor_name: string`

## Security Features

### Input Validation
- **XSS Protection**: All inputs sanitized
- **Content Filtering**: Phrases validated against security patterns
- **Length Limits**: Enforced on all text fields
- **Language Validation**: ISO language code validation

### Rate Limiting
- **Link Generation**: Limited per player per time window
- **Submission**: Limited per IP/token to prevent spam
- **Token Usage**: One-time use tokens (configurable)

### Token Security
- **Expiration**: Configurable expiration times
- **UUID Format**: Cryptographically secure tokens
- **Usage Tracking**: Monitors for abuse patterns

## Deployment Configuration

### Environment Variables
```bash
# Dynamic tunnel URL (staging only)
DYNAMIC_TUNNEL_URL=https://your-tunnel.trycloudflare.com

# Contribution settings
CONTRIBUTION_TOKEN_EXPIRY_HOURS=24
CONTRIBUTION_MAX_PHRASE_LENGTH=200
CONTRIBUTION_RATE_LIMIT=5  # per 15 minutes
```

### Docker Integration
The contribution system is automatically included when deploying game-server:

```yaml
# docker-compose.services.yml
game-server:
  environment:
    - DYNAMIC_TUNNEL_URL=${DYNAMIC_TUNNEL_URL}
```

## iOS Integration

### NetworkConfiguration.swift
```swift
// Consolidated URLs - all point to game-server
static var contributionBaseURL: String {
    return baseURL  // Uses same base as game server
}

static var contributionAPIURL: String {
    return "\(baseURL)/api/contribution/request"
}
```

### WebSocket Notifications
Players receive real-time notifications when contributions arrive:

```swift
// GameModel.swift - handles incoming phrase notifications
socket.on("phrase_received") { data in
    // Update UI with new contributed phrase
}
```

## Testing

### Manual Testing
```bash
# Generate contribution link (local)
curl -X POST http://localhost:3000/api/contribution/request \
  -H "Content-Type: application/json" \
  -d '{"playerId":"test-uuid","expirationHours":24}'

# Submit contribution
curl -X POST http://localhost:3000/api/contribution/submit \
  -H "Content-Type: application/json" \
  -d '{"token":"test-token","phrase":"test phrase","clue":"test clue"}'
```

### Automated Testing
```bash
# Run contribution system tests
node testing/scripts/test-contribution-system.js
```

## Migration Notes

### From Standalone Service (August 2025)
The link-generator service was consolidated into game-server with these changes:

1. **Endpoints Moved**: `/api/contribution/*` now served by game-server
2. **Code Consolidation**: `contribution-link-generator.js` moved to game-server
3. **Docker Removal**: link-generator service removed from docker-compose
4. **iOS Updates**: All contribution URLs now point to game-server
5. **Database Changes**: No schema changes required

### Benefits of Consolidation
- **Simpler Architecture**: 3 services instead of 4
- **Better Tunnel Compatibility**: Single entry point through Cloudflare
- **Reduced Complexity**: Fewer moving parts to maintain
- **Direct WebSocket Integration**: Real-time notifications without cross-service calls

## Troubleshooting

### Common Issues

#### Wrong IP in Contribution Links
**Problem**: Links show `192.168.1.133` instead of tunnel URL
**Solution**: Ensure `DYNAMIC_TUNNEL_URL` is set in environment

#### Token Validation Failures
**Problem**: Valid tokens rejected by server
**Solution**: Check token expiration and database connectivity

#### WebSocket Not Triggering
**Problem**: Player doesn't receive notification
**Solution**: Verify WebSocket connection and player ID matching

### Debug Commands
```bash
# Check service status
curl http://localhost:3000/api/status

# View contribution logs
docker-compose logs -f game-server | grep CONTRIBUTION

# Check token in database
docker-compose exec postgres psql -U postgres -d anagram_game \
  -c "SELECT * FROM contribution_tokens WHERE token = 'your-token';"
```

## Performance Considerations

- **Token Cleanup**: Expired tokens should be cleaned up periodically
- **Rate Limiting**: Prevents abuse and server overload
- **Database Indexing**: Ensure tokens table has proper indexes
- **WebSocket Scaling**: Consider message queuing for high-volume deployments

---

*Last Updated: August 2025*  
*Architecture: Consolidated into Game Server*  
*Status: Production Ready*