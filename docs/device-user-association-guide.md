# Device-User Association Debug Guide

## Problem
During development, you may need to associate existing users with specific devices for testing purposes. This happens when:
- Testing device-based authentication
- Switching between simulators
- Debugging login flows
- Setting up test scenarios

## Solution: Enhanced Debug Logging

### Step 1: Enable Debug Logging
The server automatically logs device IDs during registration when `NODE_ENV=development` in `.env`:

```
🔍 REGISTRATION: name='PlayerName', deviceId='1752310087_D05903D7', socketId='undefined'
```

### Step 2: Capture Device ID
1. Attempt registration from target simulator
2. Watch server logs (`tail -f server/server_output.log`)
3. Copy the deviceId from the log output

### Step 3: Update Database
Associate the captured device ID with the target user:

```bash
psql -d anagram_game -c "UPDATE players SET device_id = 'CAPTURED_DEVICE_ID' WHERE name = 'PlayerName';"
```

### Step 4: Verify
- Restart the app on the simulator
- User should now be automatically logged in

## Example Workflow
```bash
# 1. Watch logs
tail -f server/server_output.log

# 2. Try to register "TestUser" from iPhone 15 simulator
# 3. See log: 🔍 REGISTRATION: name='TestUser', deviceId='1752310087_D05903D7'
# 4. Update database
psql -d anagram_game -c "UPDATE players SET device_id = '1752310087_D05903D7' WHERE name = 'TestUser';"

# 5. Restart app - TestUser now logged in automatically on iPhone 15
```

## Safety Notes
- Only works in development mode (`NODE_ENV=development`)
- Debug logs are automatically disabled in production
- Use only for testing, not production data
- Always verify the association worked before proceeding with tests

## Alternative: Reset Device ID
If you need to test fresh registration:
```bash
# Clear device association
psql -d anagram_game -c "UPDATE players SET device_id = NULL WHERE name = 'PlayerName';"
```