# Debugging Guide

## 🚨 MANDATORY: iOS Simulator Debugging

### File-Based Logging
**Device-specific logs**: 
- `anagram-debug-iPhone-15.log`
- `anagram-debug-iPhone-15-Pro.log`

### Log Analysis Protocol
1. Run `./Scripts/tail-logs.sh` to identify most recent log file path
2. **CRITICAL**: Use device-specific logs (`anagram-debug-iPhone-15.log`) NOT old generic logs (`anagram-debug.log`)
3. Priority order: `iPhone-15.log` > `iPhone-15-Pro.log` > generic logs (avoid)
4. **YOU CAN READ iOS LOGS DIRECTLY**: Use `grep`, `head`, `tail` commands on the device-specific log file
5. Search patterns: `grep -E "(ENTERING_|GAME.*🎮|ERROR.*❌|USING_LOCAL)" /path/to/device-specific.log`
6. **ALWAYS CHECK iOS LOGS for debugging** - Don't rely only on server logs

### Code Usage
**DebugLogger Usage**: `DebugLogger.shared.ui/network/error/info/game("message")` - Add to ALL new functions

**Categories**: 
- 🎨 UI
- 🌐 NETWORK  
- ℹ️ INFO
- ❌ ERROR
- 🎮 GAME

### 🚨 CRITICAL DEBUG LOGGING RULE
- **NEVER use `print()` for debug output** - it only goes to Xcode console, not to log files
- **ALWAYS use `DebugLogger.shared.method("message")`** - this writes to log files that you can read
- **Example**: `DebugLogger.shared.network("🔍 DEBUG: Variable = \(value)")` instead of `print("🔍 DEBUG: Variable = \(value)")`

### Log Monitoring for Deployment
**🚨 LOG MONITORING**: For debugging, use device-specific logs via `./Scripts/tail-logs.sh` to find path, then `grep`/`head`/`tail` on specific device log files. **Do NOT use tail in blocking mode.**

## Common Debugging Scenarios

### WebSocket Issues
- Check server logs
- Verify NetworkManager.swift connections
- Use iOS logs to trace connection attempts

### Build Failures
- Clean derived data
- Check Info.plist versions
- Verify code signing settings

### Performance Issues
- Use Instruments for iOS profiling
- Check memory usage patterns
- Monitor frame rate drops

### Network Issues
- Verify server endpoints are accessible
- Check Docker container health
- Test from iOS simulators which connect via host network

## Docker Network Access
**⚠️ IMPORTANT**: **NEVER use localhost curl commands** - This is a legacy pattern that doesn't work with Docker containers.

- ❌ WRONG: `curl http://localhost:3000/api/status`
- ✅ CORRECT: `docker-compose -f docker-compose.services.yml exec game-server wget -q -O - http://localhost:3000/api/status`
- ✅ CORRECT: Use Docker exec to run commands inside containers
- ✅ CORRECT: Test from iOS simulators which connect via host network

## AWS ECS Debugging
- Always use `docker build --platform linux/amd64` for AWS compatibility
- Check ECS service logs for deployment issues
- Verify environment variables are properly set

## Available Tools
- **MCP Tools**: iOS Simulator control, IDE diagnostics available
- **Documentation**: 
  - `docs/device-user-association-guide.md`
  - `docs/aws-production-server-management.md`