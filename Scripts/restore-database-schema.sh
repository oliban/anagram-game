#!/bin/bash

# Database Schema Restoration Script
# Restores missing tables and data to a complete state

set -e

PI_IP="${1:-192.168.1.222}"
PI_USER="pi"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🚨 DATABASE RESTORATION SCRIPT${NC}"
echo -e "${RED}==============================${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will apply missing schema to the database!${NC}"
echo -e "${YELLOW}    This is safe and will NOT delete existing data.${NC}"
echo ""
read -p "Continue with schema restoration? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}❌ Restoration cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🔧 Restoring Database Schema on ${PI_IP}${NC}"
echo "=============================================="

# First run completeness check
echo -e "${YELLOW}📊 Running completeness check...${NC}"
if bash Scripts/check-database-completeness.sh ${PI_IP} > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Database is already complete!${NC}"
    exit 0
fi

echo -e "${YELLOW}🔧 Database needs restoration, proceeding...${NC}"
echo ""

# Schema files to apply
SCHEMA_FILES=(
    "services/shared/database/schema.sql"
)

# Apply each schema file
for schema_file in "${SCHEMA_FILES[@]}"; do
    if [ -f "$schema_file" ]; then
        echo -e "${YELLOW}📤 Applying ${schema_file}...${NC}"
        
        # Copy to Pi
        scp -q "$schema_file" ${PI_USER}@${PI_IP}:~/anagram-game/ || {
            echo -e "${RED}❌ Failed to copy schema file${NC}"
            exit 1
        }
        
        # Copy to container and apply
        FILENAME=$(basename "$schema_file")
        ssh ${PI_USER}@${PI_IP} "docker cp ~/anagram-game/${FILENAME} anagram-db:/tmp/" || {
            echo -e "${RED}❌ Failed to copy to container${NC}"
            exit 1
        }
        
        # Apply schema (ignore errors for existing objects)
        ssh ${PI_USER}@${PI_IP} "docker exec -i anagram-db psql -U postgres -d anagram_game -f /tmp/${FILENAME}" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Some schema objects already exist (this is normal)${NC}"
        }
        
        echo -e "${GREEN}✅ Applied ${FILENAME}${NC}"
    else
        echo -e "${RED}❌ Schema file not found: ${schema_file}${NC}"
        exit 1
    fi
done

echo ""
echo -e "${YELLOW}🔍 Verifying restoration...${NC}"

# Run completeness check again
if bash Scripts/check-database-completeness.sh ${PI_IP}; then
    echo ""
    echo -e "${GREEN}🎉 Database restoration successful!${NC}"
    echo -e "${GREEN}   All required tables and data are now present.${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Restoration verification failed!${NC}"
    echo -e "${YELLOW}   Manual intervention may be required.${NC}"
    exit 1
fi