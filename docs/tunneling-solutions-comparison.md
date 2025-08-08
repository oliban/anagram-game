# Tunneling Solutions for Raspberry Pi Staging Server

## 📖 Executive Summary

When running a staging server on a Raspberry Pi behind residential internet (CGNAT), you need a tunneling solution to provide global access. This document compares the main options after experiencing **rate limiting issues** with ngrok's free tier during iOS app development.

**Key Finding:** ngrok's free tier (40 requests/minute) is insufficient for active multiplayer game development, causing HTTP 429 errors and WebSocket connection failures.

---

## 🚨 The Problem We Encountered

### Rate Limiting Crisis
During iOS app testing with ngrok free:
- **Symptoms:** HTTP 429 "Too Many Requests" errors
- **Cause:** Exceeded 40 requests/minute limit
- **Impact:** WebSocket connections failed, apps stuck at "Connecting..."
- **Trigger:** Normal app behavior (2 simulators + API calls + real-time updates)

### Why Our App Hit Limits Quickly
```
Per app launch:
- /api/config/levels (skill configuration)
- /api/players/register (player registration)
- /api/phrases/for/:id (phrase fetching)
- WebSocket connection + Socket.IO events
- /api/players/stats (leaderboard updates)
- Health checks every 15 seconds

2 simulators × ~15 requests = 30 requests in first minute ⚠️
```

---

## 🔍 Solution Comparison

### Option 1: ngrok Free (Current - Problematic)
```
✅ Pros:
- Instant setup (5 minutes)
- No account required initially
- Simple command: ./ngrok http 3000

❌ Cons:
- 40 requests/minute (MAJOR BLOCKER)
- Random URLs (change on restart)
- Browser warning page
- WebSocket limitations

💰 Cost: Free
🎯 Verdict: Insufficient for development
```

### Option 2: ngrok Pro (Paid Solution)
```
✅ Pros:
- 500 requests/minute (12.5x more)
- 3 simultaneous tunnels
- Custom domains (stable URLs)
- No browser warnings
- Superior WebSocket support
- Same simple setup as free

❌ Cons:
- Monthly subscription cost
- Still vendor lock-in

💰 Cost: $8/month
🎯 Verdict: Reliable but costs money
```

### Option 3: Cloudflare Tunnel (Free Alternative)
```
✅ Pros:
- Unlimited requests (no rate limiting!)
- Free tier with good features
- Global CDN (better performance)
- Better security than ngrok
- Multiple tunnels supported
- Strong WebSocket support

❌ Cons:
- More complex setup (30-45 minutes)
- YAML configuration files
- Still random URLs on free tier
- Requires Cloudflare account
- DNS propagation delays

💰 Cost: Free (or $7/month for custom domains)
🎯 Verdict: Best value, requires setup investment
```

### Option 4: Self-Hosted Solutions
```
✅ Pros:
- Full control
- No rate limits
- Custom everything

❌ Cons:
- Requires VPS ($5-20/month)
- Significant setup complexity
- Ongoing maintenance
- Security responsibility

💰 Cost: $5-20/month + time investment
🎯 Verdict: Overkill for staging server
```

---

## 📊 Detailed Feature Matrix

| Feature | ngrok Free | ngrok Pro | Cloudflare Free | Cloudflare Paid | VPS Solution |
|---------|------------|-----------|-----------------|-----------------|--------------|
| **Rate Limiting** | 40/min ⚠️ | 500/min ✅ | None ✅ | None ✅ | None ✅ |
| **Requests/Min** | 40 | 500 | Unlimited | Unlimited | Unlimited |
| **WebSocket Quality** | Limited | Excellent | Excellent | Excellent | Excellent |
| **Custom Domains** | ❌ | ✅ | ❌ | ✅ | ✅ |
| **Stable URLs** | ❌ | ✅ | ❌ | ✅ | ✅ |
| **Setup Time** | 5 min | 5 min | 45 min | 45 min | 2-4 hours |
| **Monthly Cost** | Free | $8 | Free | $7 | $5-20 |
| **Maintenance** | None | None | Minimal | Minimal | High |
| **Global CDN** | ❌ | ❌ | ✅ | ✅ | Optional |
| **Security Features** | Basic | Good | Good | Excellent | DIY |

---

## 🎯 Recommendations by Use Case

### For Our Raspberry Pi Staging Server

#### **Immediate Solution (Next 24 hours)**
```bash
# Switch back to local testing while evaluating
# Update NetworkConfiguration.swift:
let developmentConfig = EnvironmentConfig(host: "192.168.1.133")

# Use for local development, switch to tunnel for external testing
```

#### **Short-term Solution (Next week)**
**Option A: Upgrade to ngrok Pro ($8/month)**
- Solves rate limiting immediately
- Minimal disruption to workflow
- Same simple setup process

**Option B: Implement Cloudflare Tunnel (Free)**
- Eliminates rate limiting permanently
- Better long-term solution
- Requires weekend setup session

#### **Long-term Solution (Production readiness)**
- **Cloudflare Tunnel with paid plan** ($7/month)
- Custom domain: `staging.yourdomain.com`
- Professional appearance for stakeholders
- Maximum reliability and performance

---

## 🔧 Implementation Roadmap

### Phase 1: Emergency Fix (Done ✅)
- [x] Reverted to local server for immediate testing
- [x] Documented rate limiting issues
- [x] Updated operations guide with troubleshooting

### Phase 2: Choose Solution (This Week)
```bash
# Decision Matrix:
Priority: Solve rate limiting ✅
Budget: Prefer free, accept $7-8/month for quality
Complexity: Medium acceptable for long-term benefits
Maintenance: Minimal preferred

Recommendation: Try Cloudflare Tunnel (free)
Fallback: ngrok Pro if Cloudflare setup frustrates
```

### Phase 3: Implementation
**If Cloudflare Tunnel:**
1. Set up Cloudflare account
2. Install cloudflared on Pi
3. Configure tunnel with YAML
4. Set up systemd service
5. Update iOS app configuration
6. Test thoroughly

**If ngrok Pro:**
1. Upgrade ngrok account
2. Configure custom domain
3. Update systemd service
4. Update iOS app configuration
5. Test thoroughly

### Phase 4: Documentation Update
- Update `raspberry-pi-staging-operations.md`
- Add new tunnel-specific troubleshooting
- Update reboot recovery procedures
- Document URL management process

---

## 🔍 Technical Details

### Rate Limiting Analysis
```
ngrok Free Limits:
- 40 requests/minute = 0.67 requests/second
- Our app burst rate: ~30 requests in first 30 seconds
- Sustained rate: ~4 requests/minute (health checks)
- Multi-simulator testing: 2x all above numbers

Conclusion: Even optimized app would struggle with ngrok free
```

### Performance Comparison
```
Response Time Tests (approximate):
- Local server: ~5ms
- ngrok tunnel: ~50-100ms (added latency)
- Cloudflare tunnel: ~30-70ms (better CDN)
- VPS direct: ~10-30ms (depends on location)

WebSocket Performance:
- ngrok free: Frequent disconnections due to rate limits
- ngrok pro: Stable connections
- Cloudflare: Stable connections + better global performance
```

---

## 📋 Migration Checklist

### Pre-Migration
- [ ] Document current ngrok URL
- [ ] Backup iOS app configuration
- [ ] Test local server functionality
- [ ] Plan testing timeline

### During Migration
- [ ] Set up new tunnel solution
- [ ] Configure systemd service
- [ ] Update iOS app NetworkConfiguration.swift
- [ ] Test basic connectivity
- [ ] Test WebSocket functionality
- [ ] Test multiplayer functionality

### Post-Migration
- [ ] Update operations documentation
- [ ] Test Pi reboot recovery
- [ ] Verify URL persistence (if applicable)
- [ ] Monitor for issues over 48 hours
- [ ] Update team on new URLs/process

---

## 🎯 Final Recommendation

**For the Raspberry Pi staging server: Cloudflare Tunnel (Free)**

**Reasoning:**
1. **Solves the core problem:** Eliminates rate limiting completely
2. **Cost effective:** Free tier meets current needs
3. **Future-proof:** Easy upgrade path to paid features
4. **Better performance:** Global CDN improves user experience
5. **Learning opportunity:** Valuable skill for production deployments

**Fallback plan:** If Cloudflare setup becomes frustrating, immediately switch to ngrok Pro for $8/month to unblock development.

**Timeline:** Allocate 2-3 hours for Cloudflare setup, have ngrok Pro ready as backup plan.

---

## 📞 Next Steps

1. **Decision:** Choose Cloudflare Tunnel or ngrok Pro by [DATE]
2. **Implementation:** Schedule 2-3 hour implementation window
3. **Testing:** Thorough testing with iOS apps post-migration  
4. **Monitoring:** Watch for issues in first 48 hours
5. **Documentation:** Update all operational docs with new solution

---

*Last updated: August 2025*  
*Status: Rate limiting issue identified, solutions evaluated, ready for implementation*