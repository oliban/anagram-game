#!/bin/bash

# Database Patch Runner
# Safely applies database patches in order

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="${DB_NAME:-anagram_game}"
DB_USER="${DB_USER:-$(whoami)}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

echo -e "${BLUE}🔧 Anagram Game Database Patcher${NC}"
echo "=================================="
echo -e "Database: ${YELLOW}$DB_NAME${NC}"
echo -e "Host: ${YELLOW}$DB_HOST:$DB_PORT${NC}"
echo -e "User: ${YELLOW}$DB_USER${NC}"
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ Error: psql is not installed or not in PATH${NC}"
    exit 1
fi

# Check if patches directory exists
if [ ! -d "$PATCHES_DIR" ]; then
    echo -e "${RED}❌ Error: Patches directory not found: $PATCHES_DIR${NC}"
    exit 1
fi

# Check database connection
echo -e "${BLUE}🔍 Testing database connection...${NC}"
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Cannot connect to database${NC}"
    echo "Please check:"
    echo "  - Database is running"
    echo "  - Database '$DB_NAME' exists"
    echo "  - User '$DB_USER' has access"
    echo "  - Connection parameters are correct"
    exit 1
fi
echo -e "${GREEN}✅ Database connection successful${NC}"
echo ""

# Create patches table if it doesn't exist
echo -e "${BLUE}📋 Setting up patch tracking...${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
CREATE TABLE IF NOT EXISTS database_patches (
    id SERIAL PRIMARY KEY,
    patch_name VARCHAR(255) UNIQUE NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);" >/dev/null

# Get list of applied patches
APPLIED_PATCHES=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT patch_name FROM database_patches ORDER BY patch_name;" 2>/dev/null | tr -d ' ')

# Find all patch files
PATCH_FILES=($(find "$PATCHES_DIR" -name "*.sql" | sort))

if [ ${#PATCH_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No patch files found in $PATCHES_DIR${NC}"
    exit 0
fi

echo -e "${BLUE}📝 Found ${#PATCH_FILES[@]} patch file(s)${NC}"
echo ""

# Apply patches
PATCHES_APPLIED=0
for patch_file in "${PATCH_FILES[@]}"; do
    patch_name=$(basename "$patch_file" .sql)
    
    # Check if patch is already applied
    if echo "$APPLIED_PATCHES" | grep -q "^$patch_name$"; then
        echo -e "${GREEN}✅ $patch_name${NC} - Already applied"
        continue
    fi
    
    echo -e "${YELLOW}🔄 Applying patch: $patch_name${NC}"
    
    # Apply the patch
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$patch_file" >/dev/null 2>&1; then
        # Record successful application
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            INSERT INTO database_patches (patch_name, description) 
            VALUES ('$patch_name', 'Applied by patch runner');" >/dev/null
        
        echo -e "${GREEN}✅ $patch_name${NC} - Applied successfully"
        PATCHES_APPLIED=$((PATCHES_APPLIED + 1))
    else
        echo -e "${RED}❌ $patch_name${NC} - Failed to apply"
        echo ""
        echo -e "${RED}Error output:${NC}"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$patch_file"
        exit 1
    fi
done

echo ""
if [ $PATCHES_APPLIED -gt 0 ]; then
    echo -e "${GREEN}🎉 Successfully applied $PATCHES_APPLIED new patch(es)!${NC}"
else
    echo -e "${GREEN}✅ Database is up to date - no new patches to apply${NC}"
fi

echo ""
echo -e "${BLUE}📊 Database patch status:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    patch_name as \"Patch\",
    applied_at as \"Applied At\"
FROM database_patches 
ORDER BY applied_at;
"