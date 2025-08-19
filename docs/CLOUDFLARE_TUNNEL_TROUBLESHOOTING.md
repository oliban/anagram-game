# 🌐 Cloudflare Tunnel URL Issue - Troubleshooting Guide

## 🔴 THE RECURRING PROBLEM
Contribution links and other URLs show `127.0.0.1:3000` or `localhost` instead of the Cloudflare tunnel URL `https://bras-voluntary-survivor-presidential.trycloudflare.com`

## 🎯 ROOT CAUSE
Cloudflare tunnel forwards requests with modified headers:
```javascript
// What the server receives through the tunnel:
{
  host: '127.0.0.1:3000',                    // ❌ WRONG - Local Docker address
  'x-forwarded-host': 'bras-voluntary-survivor-presidential.trycloudflare.com',  // ✅ CORRECT - Real tunnel URL
  'x-forwarded-proto': 'https',              // Protocol from tunnel
  'cf-connecting-ip': '98.128.166.174'       // Real client IP
}
```

## ✅ THE PERMANENT FIX

### 1. Always Use x-forwarded-host First
```javascript
// ✅ CORRECT implementation:
const host = req.headers['x-forwarded-host'] || req.headers.host;
const protocol = req.headers['x-forwarded-proto'] || 'http';
const baseUrl = `${protocol}://${host}`;

// ❌ WRONG - Never do this:
const baseUrl = `${protocol}://${req.headers.host}`;  // Will be 127.0.0.1!
```

### 2. Staging Environment Detection
```javascript
// ✅ CORRECT staging detection:
const isStaging = 
  process.env.NODE_ENV === 'staging' ||
  (req?.headers?.['x-forwarded-host']?.includes('trycloudflare.com'));

if (isStaging) {
  return 'https://bras-voluntary-survivor-presidential.trycloudflare.com';
}
```

## 🔧 QUICK FIX STEPS

### Step 1: Fix the Code
```bash
# Edit the contribution-link-generator.js
vim server/contribution-link-generator.js

# Find any usage of req.headers.host and change to:
# req.headers['x-forwarded-host'] || req.headers.host
```

### Step 2: Deploy the Fix
```bash
# Copy to Pi
scp server/contribution-link-generator.js pi@192.168.1.222:/home/pi/anagram-game/server/

# SSH to Pi
ssh pi@192.168.1.222

# Copy to running container (CRITICAL STEP!)
docker cp /home/pi/anagram-game/server/contribution-link-generator.js anagram-server:/project/server/

# Restart container
docker restart anagram-server
```

### Step 3: Verify the Fix
```bash
# Check the file in the container has the fix
docker exec anagram-server grep "x-forwarded-host" /project/server/contribution-link-generator.js

# Monitor logs while testing
docker logs anagram-server --follow --tail 20

# Test from iOS app and verify URLs show Cloudflare domain
```

## ⚠️ COMMON MISTAKES

### 1. Forgetting to Update Container
```bash
# ❌ WRONG - Only copying to Pi filesystem
scp file.js pi@192.168.1.222:/home/pi/anagram-game/server/

# ✅ CORRECT - Also copy into container
ssh pi@192.168.1.222 "docker cp /home/pi/anagram-game/server/file.js anagram-server:/project/server/"
```

### 2. Using Wrong Header
```javascript
// ❌ WRONG - host is always localhost in tunnel
const url = req.headers.host;

// ✅ CORRECT - x-forwarded-host has real URL
const url = req.headers['x-forwarded-host'] || req.headers.host;
```

### 3. Not Verifying Deployment
```bash
# Always verify the fix is actually deployed
docker exec anagram-server cat /project/server/contribution-link-generator.js | grep x-forwarded
```

## 📊 Test Matrix

| Environment | host Header | x-forwarded-host | Expected URL |
|------------|-------------|------------------|--------------|
| Local Dev | localhost:3000 | undefined | http://localhost:3000 |
| Pi Direct | 192.168.1.222:3000 | undefined | http://192.168.1.222:3000 |
| Cloudflare Tunnel | 127.0.0.1:3000 | bras-voluntary-survivor-presidential.trycloudflare.com | https://bras-voluntary-survivor-presidential.trycloudflare.com |

## 🔍 Debug Commands

```bash
# Check what headers the server is receiving
ssh pi@192.168.1.222 "docker logs anagram-server --tail 50" | grep "Request headers"

# Test contribution link generation
curl -X POST https://bras-voluntary-survivor-presidential.trycloudflare.com/api/contribution/request \
  -H "Content-Type: application/json" \
  -d '{"playerId": "test-id"}' | jq '.link.shareableUrl'

# Check if container has latest code
ssh pi@192.168.1.222 "docker exec anagram-server md5sum /project/server/contribution-link-generator.js"
md5sum server/contribution-link-generator.js  # Compare with local
```

## 🚨 If Issue Returns

1. **Check Git History**: `git log --grep="x-forwarded" --grep="contribution" -p`
2. **Verify Environment**: Ensure `NODE_ENV=staging` in docker-compose.yml
3. **Force Rebuild**: `docker-compose build --no-cache server`
4. **Check Headers**: Monitor actual headers being received in logs

## 📝 Prevention Checklist

- [ ] Always use `x-forwarded-host` before `host`
- [ ] Deploy changes to container, not just Pi filesystem
- [ ] Verify deployment with `docker exec` commands
- [ ] Test actual URL generation after deployment
- [ ] Document any new URL generation code with this pattern