# Device-User Association Debug Guide

## Problem
During development, you may need to associate existing users with specific devices for testing purposes. This happens when:
- Testing device-based authentication
- Switching between simulators
- Debugging login flows
- Setting up test scenarios
- After clearing simulator data (generates new device IDs)

## Solution: Enhanced Debug Logging (Microservices)

### Step 1: Monitor Docker Logs
With the microservices setup, monitor the game-server logs:

```bash
# Monitor real-time logs
docker-compose -f docker-compose.services.yml logs game-server --tail=0 -f

# Or filter for registration attempts
docker-compose -f docker-compose.services.yml logs game-server --tail=0 -f | grep -E "REGISTRATION|FAILED"
```

### Step 2: Capture Device ID from Failed Registration
1. Try to register with the existing username (e.g., "Harry") from the target simulator
2. The registration will fail with enhanced logging showing both device IDs:

```
🚫 REGISTRATION FAILED: name='Harry', deviceId='1753859611_20D42E8D', reason='NAME_TAKEN_OTHER_DEVICE', existingDeviceId='1753858974_C5C4E09B'
```

3. Copy the **new** device ID (`1753859611_20D42E8D` in this example)

### Step 3: Update Database with New Device ID
Associate the captured device ID with the existing user:

```bash
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "UPDATE players SET device_id = '1753859611_20D42E8D' WHERE name = 'Harry';"
```

### Step 4: Verify
- Try registering again with the same username on the same simulator  
- User should now be automatically logged in with their existing account and data

## Complete Example Workflow
```bash
# 1. Monitor logs for registration attempts
docker-compose -f docker-compose.services.yml logs game-server --tail=0 -f | grep -E "REGISTRATION|FAILED"

# 2. Try to register "Harry" from iPhone 15 Pro simulator (will fail)
# 3. See in logs:
# 🚫 REGISTRATION FAILED: name='Harry', deviceId='1753859611_20D42E8D', reason='NAME_TAKEN_OTHER_DEVICE', existingDeviceId='1753858974_C5C4E09B'

# 4. Update database with the NEW device ID
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "UPDATE players SET device_id = '1753859611_20D42E8D' WHERE name = 'Harry';"

# 5. Try registering "Harry" again - should now work automatically!
```

## Key Improvements Made
The enhanced logging system now captures **failed registration attempts**, making device association much faster:

- ✅ **Before**: Had to create temporary users to capture device IDs
- ✅ **After**: Failed registrations are logged with both old and new device IDs
- ✅ **Benefit**: No need for temporary users or cleanup - just try to register and capture the device ID directly

## Troubleshooting

### Multiple Simulators
When working with multiple simulators, each will generate different device IDs:
- iPhone 15: Gets device ID `1753859611_20D42E8D`
- iPhone 15 Pro: Gets device ID `1753859617_66E1D6D8`

Associate each simulator with different users for testing.

### Missing Logs
If you don't see registration logs:
1. Ensure `NODE_ENV=development` in the server's `.env` file
2. Check that the game-server container is running: `docker-compose -f docker-compose.services.yml ps`
3. Verify the enhanced logging is deployed: restart the game-server if needed

## Safety Notes
- Only works in development mode (`NODE_ENV=development`)
- Debug logs are automatically disabled in production
- Use only for testing, not production data
- Always verify the association worked before proceeding with tests

## Alternative: Reset Device ID
If you need to test fresh registration:
```bash
# Clear device association (Microservices)
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game -c "UPDATE players SET device_id = NULL WHERE name = 'PlayerName';"

# Legacy single server (deprecated)
psql -d anagram_game -c "UPDATE players SET device_id = NULL WHERE name = 'PlayerName';"
```

## Server Code Enhancement
The enhanced logging was added to `/Users/fredriksafsten/Workprojects/anagram-game/services/game-server/server.js` around line 675-679:

```javascript
// Enhanced logging for failed registrations
if (process.env.NODE_ENV === 'development') {
  console.log(`🚫 REGISTRATION FAILED: name='${name}', deviceId='${deviceId}', reason='NAME_TAKEN_OTHER_DEVICE', existingDeviceId='${nameConflict.deviceId}'`);
}
```