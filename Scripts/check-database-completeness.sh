#!/bin/bash

# Database Completeness Check Script
# Ensures all required tables exist before any operations

set -e

PI_IP="${1:-192.168.1.222}"
PI_USER="pi"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Checking Database Completeness on ${PI_IP}${NC}"
echo "=================================================="

# Required tables for complete system
REQUIRED_TABLES=(
    "players"
    "phrases" 
    "player_phrases"
    "completed_phrases"
    "skipped_phrases"
    "contribution_links"
    "offline_phrases"
    "emoji_catalog"
    "player_emoji_collections"
    "emoji_global_discoveries"
)

echo -e "${YELLOW}📊 Checking for ${#REQUIRED_TABLES[@]} required tables...${NC}"

MISSING_TABLES=()
EXISTING_TABLES=()

for table in "${REQUIRED_TABLES[@]}"; do
    EXISTS=$(ssh ${PI_USER}@${PI_IP} "docker exec -i anagram-db psql -U postgres -d anagram_game -t -c \"SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table');\"" 2>/dev/null | tr -d ' \n')
    
    if [ "$EXISTS" = "t" ]; then
        EXISTING_TABLES+=("$table")
        echo -e "  ✅ $table"
    else
        MISSING_TABLES+=("$table")
        echo -e "  ❌ $table"
    fi
done

echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  ✅ Found: ${GREEN}${#EXISTING_TABLES[@]}${NC} tables"
echo -e "  ❌ Missing: ${RED}${#MISSING_TABLES[@]}${NC} tables"

if [ ${#MISSING_TABLES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}🚨 CRITICAL: Database is incomplete!${NC}"
    echo -e "${YELLOW}Missing tables:${NC}"
    for table in "${MISSING_TABLES[@]}"; do
        echo -e "  - $table"
    done
    
    echo ""
    echo -e "${YELLOW}🔧 To fix this:${NC}"
    echo "  1. Run: bash Scripts/restore-database-schema.sh ${PI_IP}"
    echo "  2. Or manually apply missing schema files"
    echo ""
    exit 1
else
    echo ""
    echo -e "${GREEN}🎉 Database is complete! All required tables present.${NC}"
    
    # Additional checks
    echo ""
    echo -e "${YELLOW}🔍 Additional integrity checks...${NC}"
    
    # Check emoji catalog has data
    EMOJI_COUNT=$(ssh ${PI_USER}@${PI_IP} "docker exec -i anagram-db psql -U postgres -d anagram_game -t -c 'SELECT COUNT(*) FROM emoji_catalog;'" 2>/dev/null | tr -d ' \n')
    if [ "$EMOJI_COUNT" -gt 0 ]; then
        echo -e "  ✅ Emoji catalog: ${EMOJI_COUNT} emojis"
    else
        echo -e "  ⚠️  Emoji catalog is empty"
    fi
    
    # Check phrases
    PHRASE_COUNT=$(ssh ${PI_USER}@${PI_IP} "docker exec -i anagram-db psql -U postgres -d anagram_game -t -c 'SELECT COUNT(*) FROM phrases;'" 2>/dev/null | tr -d ' \n')
    echo -e "  ✅ Phrases: ${PHRASE_COUNT} total"
    
    # Check players
    PLAYER_COUNT=$(ssh ${PI_USER}@${PI_IP} "docker exec -i anagram-db psql -U postgres -d anagram_game -t -c 'SELECT COUNT(*) FROM players;'" 2>/dev/null | tr -d ' \n')
    echo -e "  ✅ Players: ${PLAYER_COUNT} registered"
    
    echo ""
    echo -e "${GREEN}✅ Database integrity verified!${NC}"
    exit 0
fi