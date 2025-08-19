# 🚀 Deployment Scripts Guide

## ⚡ **QUICK START - Daily Development**

```bash
# 🎯 Most common: Deploy code changes (10-15 seconds)
./scripts/deploy.sh [files...]

# 🔍 Verify deployment worked
./scripts/deploy.sh --check

# 🌐 Test via Cloudflare tunnel
curl -s https://bras-voluntary-survivor-presidential.trycloudflare.com/api/status
```

## 📋 **All Deployment Scripts**

### **Daily Development (90% of use cases)**
| Script | Time | Use Case | Command |
|--------|------|----------|---------|
| `deploy.sh` | 10-15s | **Deploy code changes** | `./scripts/deploy.sh` |
| `deploy.sh [files]` | 10s | **Single file changes** | `./scripts/deploy.sh server/file.js` |

### **Setup & Maintenance (Occasional)**  
| Script | Time | Use Case | Command |
|--------|------|----------|---------|
| `deploy.sh --full` | 2-5min | **Full rebuild** | `./scripts/deploy.sh --full` |
| `setup-pi.sh` | 10-15min | **New Pi server setup** | `./scripts/setup-pi.sh` |
| `check-deployment.sh` | 30s | **Verify deployment health** | `./scripts/check-deployment.sh` |

### **Database Operations**
| Script | Use Case | Command |
|--------|----------|---------|
| `import-phrases.sh` | **Add new phrases to staging** | `./scripts/import-phrases.sh data.json` |
| `backup-database.sh` | **Create database backup** | `./scripts/backup-database.sh` |
| `monitor-database.sh` | **Check database health** | `./scripts/monitor-database.sh` |

## 🎯 **Decision Tree: Which Script to Use?**

```
Need to deploy code? 
├─ Small change (1-2 files) → `./scripts/deploy.sh server/file.js` (10s)
├─ Regular development → `./scripts/deploy.sh` (10-15s) 
├─ Major changes/dependencies → `./scripts/deploy.sh --full` (2-5min)
└─ New server setup → `./scripts/setup-pi.sh` (15min)

Need to verify?
├─ Quick health check → `curl staging-url/api/status`
└─ Full verification → `./scripts/check-deployment.sh`

Database operations?
├─ Add phrases → `./scripts/import-phrases.sh data.json`
├─ Backup → `./scripts/backup-database.sh`  
└─ Health check → `./scripts/monitor-database.sh`
```

## ⚠️ **Common Mistakes to Avoid**

### ❌ **Wrong:**
```bash
# Don't use these confusing legacy names
bash Scripts/deploy-to-pi.sh        # Old, slow
bash Scripts/deploy-staging.sh      # Confusing name
scp file.js pi@192.168.1.222:...    # Manual, error-prone
```

### ✅ **Correct:**
```bash
# Use the unified deployment script
./scripts/deploy.sh                 # Fast, reliable
./scripts/deploy.sh server/file.js  # Targeted deployment
./scripts/deploy.sh --full          # When needed
```

## 🔧 **Environment Variables**

```bash
# Override Pi IP if needed
PI_HOST=192.168.1.222 ./scripts/deploy.sh

# Force cleanup
FORCE_CLEAN=true ./scripts/deploy.sh --full
```

## 📞 **Troubleshooting**

| Problem | Solution |
|---------|----------|
| "Container not found" | `./scripts/deploy.sh --full` |
| "Service not responding" | Wait 30s, then check logs |
| "Cloudflare 502 error" | Pi containers stopped, restart |
| "Wrong URL in links" | See `docs/CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md` |

## 🚨 **Emergency Recovery**

```bash
# If staging is completely broken
./scripts/setup-pi.sh --reset

# If database is corrupted  
./scripts/backup-database.sh --restore
```