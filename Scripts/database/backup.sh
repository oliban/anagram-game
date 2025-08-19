#!/bin/bash

# Automated Database Backup Script
# Creates timestamped backups before dangerous operations

set -e

PI_IP="${1:-192.168.1.222}"
PI_USER="pi"
BACKUP_DIR="database-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}💾 Creating Database Backup${NC}"
echo "================================"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/anagram_game_backup_${TIMESTAMP}.sql"

echo -e "${YELLOW}📤 Creating backup: $(basename $BACKUP_FILE)${NC}"

# Create backup
ssh ${PI_USER}@${PI_IP} "docker exec anagram-db pg_dump -U postgres -d anagram_game --clean --create" > "$BACKUP_FILE" 2>/dev/null

if [ -s "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}✅ Backup created successfully${NC}"
    echo -e "   File: $BACKUP_FILE"
    echo -e "   Size: $BACKUP_SIZE"
    
    # Keep only last 5 backups
    ls -t ${BACKUP_DIR}/anagram_game_backup_*.sql | tail -n +6 | xargs -r rm
    
    BACKUP_COUNT=$(ls ${BACKUP_DIR}/anagram_game_backup_*.sql 2>/dev/null | wc -l)
    echo -e "   Total backups: $BACKUP_COUNT (keeping last 5)"
    
    exit 0
else
    echo -e "${RED}❌ Backup failed or empty${NC}"
    rm -f "$BACKUP_FILE" 2>/dev/null
    exit 1
fi