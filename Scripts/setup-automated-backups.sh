#!/bin/bash

# Automated Backup System Setup
# Sets up cron jobs and backup policies on the Pi

set -e

PI_IP="${1:-192.168.1.222}"
PI_USER="pi"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}⚡ Setting Up Automated Backup System${NC}"
echo "==========================================="

# Step 1: Create backup directories on Pi
echo -e "${YELLOW}📁 Setting up backup directories...${NC}"
ssh ${PI_USER}@${PI_IP} "mkdir -p ~/anagram-game/backups/{daily,weekly,monthly,emergency}"
echo -e "${GREEN}✅ Backup directories created${NC}"

# Step 2: Copy backup scripts to Pi
echo -e "${YELLOW}📤 Deploying backup scripts...${NC}"
ssh ${PI_USER}@${PI_IP} "mkdir -p ~/anagram-game/scripts"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -q "${SCRIPT_DIR}/backup-database.sh" ${PI_USER}@${PI_IP}:~/anagram-game/scripts/backup-database.sh
ssh ${PI_USER}@${PI_IP} "chmod +x ~/anagram-game/scripts/backup-database.sh"

# Step 3: Create enhanced backup script on Pi
echo -e "${YELLOW}🔧 Creating enhanced backup script on Pi...${NC}"
ssh ${PI_USER}@${PI_IP} "cat > ~/anagram-game/scripts/daily-backup.sh << 'EOF'
#!/bin/bash
# Daily Backup Script - Runs on Pi

set -e

BACKUP_TYPE=\${1:-daily}
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=\"\$HOME/anagram-game/backups/\$BACKUP_TYPE\"
BACKUP_FILE=\"\$BACKUP_DIR/anagram_game_\${BACKUP_TYPE}_\${TIMESTAMP}.sql\"

# Create backup
mkdir -p \"\$BACKUP_DIR\"
docker exec anagram-db pg_dump -U postgres -d anagram_game --clean --create > \"\$BACKUP_FILE\" 2>/dev/null

if [ -s \"\$BACKUP_FILE\" ]; then
    # Compress backup
    gzip \"\$BACKUP_FILE\"
    BACKUP_FILE=\"\${BACKUP_FILE}.gz\"
    
    echo \"[$(date)] \$BACKUP_TYPE backup created: \$(basename \$BACKUP_FILE)\" >> \$HOME/anagram-game/backups/backup.log
    
    # Retention policy
    case \$BACKUP_TYPE in
        daily)
            # Keep 7 daily backups
            ls -t \$BACKUP_DIR/anagram_game_daily_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
            ;;
        weekly)
            # Keep 4 weekly backups
            ls -t \$BACKUP_DIR/anagram_game_weekly_*.sql.gz 2>/dev/null | tail -n +5 | xargs -r rm
            ;;
        monthly)
            # Keep 12 monthly backups
            ls -t \$BACKUP_DIR/anagram_game_monthly_*.sql.gz 2>/dev/null | tail -n +13 | xargs -r rm
            ;;
    esac
    
    exit 0
else
    echo \"[$(date)] ERROR: \$BACKUP_TYPE backup failed\" >> \$HOME/anagram-game/backups/backup.log
    rm -f \"\$BACKUP_FILE\" 2>/dev/null
    exit 1
fi
EOF"

# Make it executable
ssh ${PI_USER}@${PI_IP} "chmod +x ~/anagram-game/scripts/daily-backup.sh"
echo -e "${GREEN}✅ Enhanced backup script deployed${NC}"

# Step 4: Set up cron jobs
echo -e "${YELLOW}⏰ Setting up automated backup schedule...${NC}"
ssh ${PI_USER}@${PI_IP} "
# Remove any existing anagram backup cron jobs
crontab -l 2>/dev/null | grep -v 'anagram-game/scripts' | crontab -

# Add new cron jobs
(crontab -l 2>/dev/null; echo '# Anagram Game Database Backups')
(crontab -l 2>/dev/null; echo '15 2 * * * \$HOME/anagram-game/scripts/daily-backup.sh daily >> \$HOME/anagram-game/backups/cron.log 2>&1')
(crontab -l 2>/dev/null; echo '30 3 * * 0 \$HOME/anagram-game/scripts/daily-backup.sh weekly >> \$HOME/anagram-game/backups/cron.log 2>&1')
(crontab -l 2>/dev/null; echo '45 4 1 * * \$HOME/anagram-game/scripts/daily-backup.sh monthly >> \$HOME/anagram-game/backups/cron.log 2>&1') | crontab -
"
echo -e "${GREEN}✅ Backup schedule configured${NC}"
echo "   📅 Daily: 2:15 AM (keep 7 days)"
echo "   📅 Weekly: 3:30 AM Sunday (keep 4 weeks)"
echo "   📅 Monthly: 4:45 AM 1st of month (keep 12 months)"

# Step 5: Create immediate backup to test
echo -e "${YELLOW}🧪 Testing backup system...${NC}"
if ssh ${PI_USER}@${PI_IP} "~/anagram-game/scripts/daily-backup.sh emergency"; then
    echo -e "${GREEN}✅ Test backup successful${NC}"
else
    echo -e "${RED}❌ Test backup failed${NC}"
    exit 1
fi

# Step 6: Create backup monitoring script
echo -e "${YELLOW}📊 Setting up backup monitoring...${NC}"
ssh ${PI_USER}@${PI_IP} "cat > ~/anagram-game/scripts/check-backup-health.sh << 'EOF'
#!/bin/bash
# Backup Health Check Script

BACKUP_DIR=\"\$HOME/anagram-game/backups\"
NOW=\$(date +%s)

echo \"🔍 Backup System Health Check - \$(date)\"
echo \"=========================================\"

# Check daily backups
LATEST_DAILY=\$(ls -t \$BACKUP_DIR/daily/*.gz 2>/dev/null | head -1)
if [ -n \"\$LATEST_DAILY\" ]; then
    DAILY_AGE=\$((\$NOW - \$(stat -c %Y \"\$LATEST_DAILY\")))
    DAILY_HOURS=\$((\$DAILY_AGE / 3600))
    echo \"✅ Latest daily backup: \$(basename \$LATEST_DAILY) (\$DAILY_HOURS hours ago)\"
    
    if [ \$DAILY_HOURS -gt 25 ]; then
        echo \"⚠️  WARNING: Daily backup is over 25 hours old!\"
    fi
else
    echo \"❌ No daily backups found!\"
fi

# Backup counts
DAILY_COUNT=\$(ls \$BACKUP_DIR/daily/*.gz 2>/dev/null | wc -l)
WEEKLY_COUNT=\$(ls \$BACKUP_DIR/weekly/*.gz 2>/dev/null | wc -l)
MONTHLY_COUNT=\$(ls \$BACKUP_DIR/monthly/*.gz 2>/dev/null | wc -l)
EMERGENCY_COUNT=\$(ls \$BACKUP_DIR/emergency/*.gz 2>/dev/null | wc -l)

echo \"📊 Backup counts:\"
echo \"   Daily: \$DAILY_COUNT/7\"
echo \"   Weekly: \$WEEKLY_COUNT/4\"
echo \"   Monthly: \$MONTHLY_COUNT/12\"
echo \"   Emergency: \$EMERGENCY_COUNT\"

# Disk usage
BACKUP_SIZE=\$(du -sh \$BACKUP_DIR 2>/dev/null | cut -f1)
echo \"💾 Total backup size: \$BACKUP_SIZE\"

echo \"\"
echo \"📝 Recent backup log:\"
tail -5 \$BACKUP_DIR/backup.log 2>/dev/null || echo \"No backup log found\"
EOF"

ssh ${PI_USER}@${PI_IP} "chmod +x ~/anagram-game/scripts/check-backup-health.sh"
echo -e "${GREEN}✅ Backup monitoring script created${NC}"

# Step 7: Show backup status
echo ""
echo -e "${BLUE}📊 Current Backup Status${NC}"
echo "========================="
ssh ${PI_USER}@${PI_IP} "~/anagram-game/scripts/check-backup-health.sh"

echo ""
echo -e "${GREEN}🎉 Automated Backup System Setup Complete!${NC}"
echo ""
echo "📋 Management commands:"
echo "   Check status: ssh ${PI_USER}@${PI_IP} '~/anagram-game/scripts/check-backup-health.sh'"
echo "   Manual backup: ssh ${PI_USER}@${PI_IP} '~/anagram-game/scripts/daily-backup.sh emergency'"
echo "   View logs: ssh ${PI_USER}@${PI_IP} 'tail -f ~/anagram-game/backups/backup.log'"
echo "   View cron schedule: ssh ${PI_USER}@${PI_IP} 'crontab -l | grep anagram'"