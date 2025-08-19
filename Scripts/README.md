# 🚀 Deployment Scripts

## ⚡ **QUICK START**

```bash
# 🎯 Deploy code changes (most common - 10-15 seconds)
./scripts/deploy.sh

# 🔍 Check if everything is working  
./scripts/deploy.sh --check

# 🏗️ Full rebuild (only when needed - 2-5 minutes)
./scripts/deploy.sh --full
```

## 📋 **All Commands**

| Command | Time | Use Case |
|---------|------|----------|
| `./scripts/deploy.sh` | **10-15s** | **Deploy server changes (daily use)** |
| `./scripts/deploy.sh server/file.js` | **10s** | **Deploy single file** |
| `./scripts/deploy.sh --check` | **5s** | **Verify deployment health** |
| `./scripts/deploy.sh --full` | **2-5min** | **Full rebuild (major changes)** |
| `./scripts/import-phrases.sh data.json` | **30s** | **Add new phrases** |
| `./scripts/database/backup.sh` | **10s** | **Backup database** |

## 🎯 **Decision Tree**

```
What do you need to do?

├─ Deploy code changes?
│  ├─ Small fix → ./scripts/deploy.sh server/file.js
│  ├─ Regular dev → ./scripts/deploy.sh  
│  └─ Major changes → ./scripts/deploy.sh --full
│
├─ Check if working?
│  └─ ./scripts/deploy.sh --check
│
└─ Database work?
   ├─ Add phrases → ./scripts/import-phrases.sh
   └─ Backup → ./scripts/database/backup.sh
```

## ⚙️ **Environment**

```bash
# Use different Pi
PI_HOST=192.168.1.100 ./scripts/deploy.sh

# Get help
./scripts/deploy.sh --help
```

## 🚨 **Troubleshooting**

| Problem | Solution |
|---------|----------|
| "Cannot reach Pi" | Check Pi is on, connected to WiFi |
| "Service not responding" | Try `./scripts/deploy.sh --full` |
| "Wrong URLs in links" | See `docs/CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md` |