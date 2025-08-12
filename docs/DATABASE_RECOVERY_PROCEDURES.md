# Database Recovery Procedures

## 🚨 CRITICAL RECOVERY GUIDE

This document provides step-by-step procedures for recovering from database failures, corruption, or data loss incidents.

**When to use**: Database unavailable, missing tables, data corruption, or failed migrations.

## 🚦 RECOVERY PRIORITY MATRIX

### Level 1: Service Unavailable (CRITICAL)
- **Symptoms**: 500 errors, "relation does not exist", Docker container won't start
- **Priority**: IMMEDIATE (< 15 minutes)
- **Action**: Complete database restore from backup

### Level 2: Partial Data Loss (HIGH)
- **Symptoms**: Missing tables, incomplete schema, some features broken
- **Priority**: URGENT (< 1 hour)
- **Action**: Schema restoration + selective data recovery

### Level 3: Data Inconsistency (MEDIUM) 
- **Symptoms**: Wrong counts, missing relationships, corrupt data
- **Priority**: HIGH (< 4 hours)
- **Action**: Data validation + repair procedures

## 📋 PRE-RECOVERY CHECKLIST

Before starting any recovery:

```bash
# 1. Document current state
ssh pi@192.168.1.222 'docker logs anagram-db --tail 50 > ~/recovery-logs.txt'

# 2. Check available backups
ssh pi@192.168.1.222 '~/anagram-game/scripts/check-backup-health.sh'

# 3. Create emergency snapshot (if database is accessible)
ssh pi@192.168.1.222 '~/anagram-game/scripts/daily-backup.sh emergency'

# 4. Notify team
echo "🚨 Database recovery initiated at $(date)" >> recovery-log.md
```

## 🔧 COMPLETE DATABASE RESTORATION

### Scenario: Total Database Loss/Corruption

**Estimated Time**: 10-15 minutes

```bash
# Step 1: Stop services to prevent data conflicts
ssh pi@192.168.1.222 'cd ~/anagram-game && docker-compose -f docker-compose.services.yml down'

# Step 2: Stop and remove database container
ssh pi@192.168.1.222 'docker stop anagram-db && docker rm anagram-db'

# Step 3: Remove corrupted volume
ssh pi@192.168.1.222 'docker volume rm anagram-game_postgres_data || true'

# Step 4: Find latest backup
LATEST_BACKUP=$(ssh pi@192.168.1.222 'ls -t ~/anagram-game/backups/daily/*.gz 2>/dev/null | head -1')
echo "📦 Using backup: $(basename $LATEST_BACKUP)"

# Step 5: Recreate database container
ssh pi@192.168.1.222 'cd ~/anagram-game && docker-compose -f docker-compose.services.yml up -d postgres'

# Wait for database to be ready
echo "⏳ Waiting for database to initialize..."
sleep 30

# Step 6: Restore from backup
ssh pi@192.168.1.222 "gunzip < $LATEST_BACKUP | docker exec -i anagram-db psql -U postgres"

# Step 7: Verify restoration
ssh pi@192.168.1.222 'docker exec anagram-db psql -U postgres -d anagram_game -c "\dt" | wc -l'
# Should show 10+ tables

# Step 8: Restart all services
ssh pi@192.168.1.222 'cd ~/anagram-game && docker-compose -f docker-compose.services.yml up -d'

# Step 9: Verify functionality
curl -s "http://192.168.1.222:3000/api/status" | grep "healthy"
```

## 🔨 SCHEMA-ONLY RESTORATION

### Scenario: Missing Tables, Incomplete Schema

**Estimated Time**: 5-10 minutes

```bash
# Step 1: Check current schema state
bash Scripts/check-database-completeness.sh 192.168.1.222

# Step 2: Auto-restore missing schema
bash Scripts/restore-database-schema.sh 192.168.1.222

# Step 3: Verify all tables present
bash Scripts/check-database-completeness.sh 192.168.1.222
```

## 📊 SELECTIVE DATA RECOVERY

### Scenario: Specific Table Data Loss

**Example**: Emoji tables missing but core phrases intact

```bash
# Step 1: Identify missing data
ssh pi@192.168.1.222 'docker exec anagram-db psql -U postgres -d anagram_game -c "SELECT COUNT(*) FROM emoji_catalog;"'

# Step 2: Extract specific table from backup
LATEST_BACKUP=$(ssh pi@192.168.1.222 'ls -t ~/anagram-game/backups/daily/*.gz | head -1')

# Step 3: Restore specific table
ssh pi@192.168.1.222 "
gunzip < $LATEST_BACKUP | 
grep -A 1000 'CREATE TABLE emoji_catalog' |
grep -B 1000 'CREATE TABLE [^e]' |
head -n -1 |
docker exec -i anagram-db psql -U postgres -d anagram_game
"

# Step 4: Verify data
ssh pi@192.168.1.222 'docker exec anagram-db psql -U postgres -d anagram_game -c "SELECT COUNT(*) FROM emoji_catalog;"'
```

## 🚀 EMERGENCY REBUILD PROCEDURES

### When All Backups Are Corrupted/Lost

**⚠️ USE ONLY AS LAST RESORT**

```bash
# Step 1: Nuclear option - complete rebuild
ssh pi@192.168.1.222 'cd ~/anagram-game && docker-compose -f docker-compose.services.yml down -v'

# Step 2: Rebuild with fresh schema
ssh pi@192.168.1.222 'cd ~/anagram-game && docker-compose -f docker-compose.services.yml up -d postgres'
sleep 30

# Step 3: Apply complete schema
scp services/shared/database/schema.sql pi@192.168.1.222:~/schema.sql
ssh pi@192.168.1.222 'docker exec -i anagram-db psql -U postgres < ~/schema.sql'

# Step 4: Re-import core phrases
bash Scripts/import-phrases-staging.sh server/data/imported/imported-on-stage/*.json --limit 200

# Step 5: Recreate test users
# (Manual step - coordinate with team for user recreation)
```

## 🔍 POST-RECOVERY VERIFICATION

### Mandatory Checks After Any Recovery

```bash
# 1. Database completeness
bash Scripts/check-database-completeness.sh 192.168.1.222

# Expected output:
# ✅ Found: 10/10 required tables
# ✅ Emoji catalog: 53 emojis
# ✅ Phrases: [number] total

# 2. API functionality
curl -s "http://192.168.1.222:3000/api/status" | grep "healthy"

# 3. Sample phrase retrieval
curl -s "http://192.168.1.222:3000/api/phrases/global?limit=5" | jq '.phrases | length'

# 4. Test known player
curl -s "http://192.168.1.222:3000/api/phrases/for/[player-id]?level=1" | jq '.phrases | length'

# 5. Check logs for errors
ssh pi@192.168.1.222 'docker logs anagram-game-server --tail 20 | grep -E "(ERROR|Failed|failed)"'
```

## 📱 RECOVERY VALIDATION CHECKLIST

Post-recovery, verify these functions:

- [ ] **Database Connection**: Services can connect to PostgreSQL
- [ ] **Table Completeness**: All 10 required tables exist
- [ ] **Emoji System**: 53 emojis in catalog
- [ ] **Phrase Retrieval**: Players can get phrases
- [ ] **Global Phrases**: Anonymous access works
- [ ] **API Health**: Status endpoint returns "healthy"
- [ ] **iOS App**: Can connect and get phrases
- [ ] **No 500 Errors**: Check recent logs

## 🚨 INCIDENT RESPONSE WORKFLOW

### During Recovery Emergency

1. **Immediate Response** (0-5 min):
   ```bash
   # Document the incident
   echo "$(date): Database failure detected" >> ~/recovery-incident.log
   
   # Check backup availability
   ssh pi@192.168.1.222 '~/anagram-game/scripts/check-backup-health.sh'
   
   # Inform stakeholders
   echo "🚨 Database recovery in progress, ETA 15 minutes"
   ```

2. **Recovery Execution** (5-20 min):
   - Choose appropriate recovery procedure based on symptoms
   - Execute step-by-step with logging
   - Monitor progress and adjust as needed

3. **Verification** (20-25 min):
   - Run all validation checks
   - Test critical user journeys
   - Monitor for 10 minutes post-recovery

4. **Documentation** (25-30 min):
   - Update incident log with timeline
   - Document root cause if identified
   - Create prevention measures if needed

## 🛡️ PREVENTION BEST PRACTICES

### Before Making Changes

```bash
# Always create backup before risky operations
bash Scripts/backup-database.sh 192.168.1.222

# Verify schema completeness
bash Scripts/check-database-completeness.sh 192.168.1.222

# Test in development first
# Never apply untested changes to production
```

### Regular Maintenance

```bash
# Weekly health check
ssh pi@192.168.1.222 '~/anagram-game/scripts/check-backup-health.sh'

# Monthly backup validation
# Restore a backup to test environment and verify integrity

# Quarterly disaster recovery drill
# Practice full recovery procedure with team
```

## 📚 RECOVERY SCRIPT REFERENCE

### Available Recovery Scripts

```bash
# Database health and completeness
Scripts/check-database-completeness.sh [pi-ip]

# Schema restoration (non-destructive)
Scripts/restore-database-schema.sh [pi-ip]

# Backup creation
Scripts/backup-database.sh [pi-ip]

# Backup system health
ssh pi@[ip] '~/anagram-game/scripts/check-backup-health.sh'

# Full import pipeline (safe)
Scripts/import-phrases-staging.sh [files] [options]
```

### Emergency Contact Information

- **Database Issues**: Check CLAUDE.md for current protocols
- **Backup Failures**: Verify cron jobs and disk space
- **Schema Problems**: Always use restore-database-schema.sh
- **Performance Issues**: Check Docker logs and system resources

---

## 🎯 COMMON RECOVERY SCENARIOS

### "Bruno is out of phrases"
1. Check phrase serving logic in DatabasePhrase.js:262
2. Verify difficulty filtering is working
3. Check if player has completed all available phrases
4. Solution: Import more phrases or adjust difficulty logic

### "500 Error: relation does not exist"
1. Identify missing table from error logs
2. Run schema restoration: `bash Scripts/restore-database-schema.sh`
3. Verify with completeness check
4. Restart services

### "No backups available"
1. Check cron jobs: `ssh pi@ip 'crontab -l | grep anagram'`
2. Verify backup script permissions and paths
3. Run manual backup: `ssh pi@ip '~/anagram-game/scripts/daily-backup.sh emergency'`
4. Check disk space and Docker volume status

### "Database won't start"
1. Check Docker logs: `ssh pi@ip 'docker logs anagram-db'`
2. Verify volume integrity: `docker volume inspect anagram-game_postgres_data`
3. Check system resources: `df -h && free -h`
4. Nuclear option: Remove volume and restore from backup

---

**Remember**: Always choose the least destructive recovery method that addresses the specific issue. When in doubt, create a backup before attempting any recovery procedure.