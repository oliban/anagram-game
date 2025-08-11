# Security Guide

## 🛡️ IMPLEMENTED SECURITY FEATURES (Phase 1 Complete)

### Environment Security
- **✅ Flexible dev/prod configuration** with secure defaults
- Environment-specific security settings
- Secure default configurations for production

### CORS Hardening
- **✅ Restricted origins**:
  - Development: `origin: true` (relaxed for local development)
  - Production: Domain whitelist enforcement
- Cross-origin protection configured per environment

### Rate Limiting
- **✅ Realistic limits** for word game usage patterns:
  - **Game Server**: 120/30 requests per 15min (dev/prod) = ~8-2 per minute
  - **Web Dashboard**: 300/60 = ~20-4 per minute (dashboard polling)
- Rate limiting headers included in responses

### Input Validation
- **✅ XSS/SQL injection protection** with Joi + express-validator
- **Security patterns**: `/^[a-zA-Z0-9\s\-_.,!?'"()åäöÅÄÖ]*$/` for safe text
- **UUID validation** for IDs
- **Language code validation**
- **Sanitization** for database inputs and output display

## 🔧 SECURITY CONFIGURATION

### Environment Variables
```bash
# Automatically set in development:
SECURITY_RELAXED=true          # Enables relaxed CORS in development
LOG_SECURITY_EVENTS=true       # Logs CORS violations and security events
SKIP_RATE_LIMITS=false         # Rate limits active (set true to disable for testing)
ADMIN_API_KEY=test-admin-key-123 # For admin endpoint authentication (Phase 2)
```

### Development vs Production Settings

#### Development Mode
- Relaxed CORS policies
- Detailed security event logging
- Test API keys
- Flexible rate limits

#### Production Mode
- Strict CORS enforcement
- Domain whitelist only
- Secure API key management
- Enforced rate limits

## 🚨 SECURITY TESTING COMMANDS

### Comprehensive Security Test Suite ✅ COMPLETE

#### Automated Security Testing
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

# Admin endpoints removed - use direct database script for testing
node scripts/phrase-importer.js --input malicious.json --dry-run  # Safe validation test

# Monitor security events
docker-compose -f docker-compose.services.yml logs | grep -E "(🛡️|🔑|🚫|❌)"

# Direct database import (secure replacement)
node scripts/phrase-importer.js --input valid-phrases.json --import
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

## 📋 REMAINING SECURITY TASKS (Phase 2)

### iOS Security Enhancements
- **Keychain integration** for sensitive data storage
- **HTTPS only** enforcement
- **Certificate pinning** for API connections
- **Secure token storage**

### Backend Security Enhancements
- **Admin API key authentication** implementation
- **WebSocket security** hardening
- **JWT token management** (if needed)
- **Database encryption** for sensitive fields

### Security Monitoring
- **Security event dashboards** setup
- **Failed authentication tracking**
- **Intrusion detection** alerts
- **Automated security scanning**

## 🔍 SECURITY CHECKS

### Regular Security Audits
```bash
# Check for hardcoded secrets
grep -r "password\|secret\|key" --exclude-dir=node_modules --exclude-dir=.git .

# Check for vulnerabilities in dependencies
npm audit

# Verify rate limit headers in API responses
curl -I http://localhost:3000/api/status | grep -i ratelimit

# Check Docker security
docker scan [image-name]
```

### Configuration Verification
- **CORS configuration** in server logs: Look for `🔧 CORS Configuration`
- **Rate limiting configuration** in logs: Look for `🛡️ Rate Limiting Configuration`
- **Environment variable security** review
- **Database connection security** verification

## 🔒 SECURITY UPDATE: Admin API Endpoints Removed

### What Changed
- **REMOVED**: All admin batch import endpoints (HTTP API)
- **REMOVED**: Admin Service HTTP-based bulk operations
- **REPLACED**: Direct database script access only

### Benefits
- **No network exposure** for admin operations
- **Better performance** with direct database access
- **Reduced attack surface** - no HTTP endpoints to exploit
- **Cleaner architecture** - fewer services to secure

### New Import Method
```bash
# Secure direct database access
node scripts/phrase-importer.js --input file.json --import

# No HTTP API required
# No network requests
# Direct PostgreSQL operations only
```

## 🚨 SECURITY BEST PRACTICES

### Development Guidelines
1. **Never commit** secrets or API keys to repositories
2. **Use environment variables** for all sensitive configuration
3. **Test security features** regularly with provided scripts
4. **Monitor security events** during development
5. **Validate all inputs** before processing
6. **Sanitize outputs** before sending to clients

### Production Guidelines
1. **Enable strict security mode** with `SECURITY_RELAXED=false`
2. **Use strong API keys** and rotate them regularly
3. **Monitor rate limiting** and adjust as needed
4. **Review security logs** daily
5. **Update dependencies** regularly
6. **Use HTTPS only** in production
7. **Implement proper CORS** domain whitelisting

### Emergency Response
1. **Security incident detected**:
   - Enable strict security mode immediately
   - Review security logs for attack patterns
   - Block suspicious IP addresses at firewall level
   - Rotate all API keys and credentials

2. **Vulnerability discovered**:
   - Assess impact and affected systems
   - Apply security patches immediately
   - Update security tests to prevent regression
   - Document incident and response

## 🔍 Security Event Monitoring

### Log Analysis
Security events are logged with specific emojis for easy filtering:
- 🛡️ Security configuration events
- 🔑 Authentication events
- 🚫 Access denied events
- ❌ Error events (potential security issues)
- 🔧 Configuration changes

### Real-time Monitoring
```bash
# Watch all security-related events
docker-compose -f docker-compose.services.yml logs -f | grep -E "(🛡️|🔑|🚫|❌|AUTH|CORS|SECURITY)"

# Monitor specific security patterns
docker-compose -f docker-compose.services.yml logs -f | grep -E "(BLOCKED|DENIED|UNAUTHORIZED|VIOLATION)"
```

### Security Metrics to Track
- Rate limit violations per hour
- CORS violations per day
- Failed authentication attempts
- Invalid input attempts (XSS, injection)
- Unusual traffic patterns