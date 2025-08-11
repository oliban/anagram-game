#!/bin/bash

# Phrase Import Script for Staging (Docker Environment)
# Run this script locally - it handles all remote operations
# Supports multiple files and wildcards

set -e

# Configuration
PI_IP="192.168.1.222"
PI_USER="pi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to show usage
show_usage() {
    echo "Usage: $0 <phrase-json-files...> [options]"
    echo ""
    echo "Arguments:"
    echo "  <phrase-json-files>  Path(s) to JSON file(s) containing phrases to import"
    echo "                       Supports wildcards: server/data/imported/*.json"
    echo ""
    echo "Options:"
    echo "  --deploy            Deploy/restart staging services before import"
    echo "  --limit <n>         Limit number of phrases per file to import (default: 50)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 server/data/imported/phrases-sv.json"
    echo "  $0 server/data/imported/*.json --limit 30"
    echo "  $0 file1.json file2.json file3.json --deploy"
    echo ""
    echo "Note: Successfully imported files are automatically moved to imported-on-stage/"
    echo ""
    echo "This script runs LOCALLY and handles all remote operations automatically."
    exit 1
}

# Parse arguments
if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
    show_usage
fi

# Collect all file arguments until we hit an option
PHRASE_FILES=()
while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
    # Expand wildcards if present
    for file in $1; do
        if [ -f "$file" ]; then
            PHRASE_FILES+=("$file")
        fi
    done
    shift
done

# Check if we found any files
if [ ${#PHRASE_FILES[@]} -eq 0 ]; then
    echo -e "${RED}❌ Error: No valid files found${NC}"
    echo "Make sure you're running this from the project root directory"
    exit 1
fi

DEPLOY_FIRST=false
IMPORT_LIMIT=50

# Parse additional options
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy)
            DEPLOY_FIRST=true
            shift
            ;;
        --limit)
            IMPORT_LIMIT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

echo -e "${BLUE}🚀 Importing Phrases to Staging Server${NC}"
echo "====================================="
echo -e "📄 Files to import: ${YELLOW}${#PHRASE_FILES[@]}${NC}"
for file in "${PHRASE_FILES[@]}"; do
    echo "    - $(basename "$file")"
done
echo -e "🎯 Target: ${YELLOW}$PI_USER@$PI_IP${NC}"
echo -e "📊 Limit: ${YELLOW}$IMPORT_LIMIT phrases per file${NC}"
echo ""

# Step 1: Optional deployment
if [ "$DEPLOY_FIRST" = true ]; then
    echo -e "${YELLOW}📦 Deploying staging services...${NC}"
    if [ -f "Scripts/deploy-to-pi.sh" ]; then
        bash Scripts/deploy-to-pi.sh
    elif [ -f "scripts/deploy-staging.sh" ]; then
        bash scripts/deploy-staging.sh
    else
        echo -e "${YELLOW}⚠️  Deployment script not found, skipping deployment${NC}"
    fi
fi

# Step 2: Test SSH connection
echo -e "${YELLOW}🔗 Testing connection to Pi...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${PI_USER}@${PI_IP} "echo 'Connected'" > /dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to Pi at ${PI_IP}${NC}"
    echo "Please check:"
    echo "  1. Pi is powered on and connected to network"
    echo "  2. SSH service is running on Pi"
    echo "  3. Your SSH key is configured"
    exit 1
fi
echo -e "${GREEN}✅ Connection successful${NC}"

# Step 3: Ensure directories exist on Pi
echo -e "${YELLOW}📁 Preparing remote directories...${NC}"
ssh ${PI_USER}@${PI_IP} "mkdir -p ~/anagram-game/server/data/imported"
echo -e "${GREEN}✅ Directories ready${NC}"

# Step 4: Check if Docker services are running
echo -e "${YELLOW}🐳 Checking Docker services...${NC}"
SERVICE_STATUS=$(ssh ${PI_USER}@${PI_IP} "cd ~/anagram-game && docker-compose -f docker-compose.services.yml ps -q game-server 2>/dev/null" || echo "")

if [ -z "$SERVICE_STATUS" ]; then
    echo -e "${YELLOW}⚠️  Services not running, starting them...${NC}"
    ssh ${PI_USER}@${PI_IP} "cd ~/anagram-game && docker-compose -f docker-compose.services.yml up -d" > /dev/null 2>&1
    echo "Waiting for services to be ready..."
    sleep 10
fi
echo -e "${GREEN}✅ Docker services ready${NC}"

# Step 5: Copy import script to staging
echo -e "${YELLOW}📤 Deploying import script...${NC}"
IMPORT_SCRIPT=""
if [ -f "import-phrases.js" ]; then
    IMPORT_SCRIPT="import-phrases.js"
elif [ -f "../import-phrases.js" ]; then
    IMPORT_SCRIPT="../import-phrases.js"
else
    echo -e "${RED}❌ Cannot find import-phrases.js in project root${NC}"
    echo "Please ensure import-phrases.js exists in the project root directory"
    exit 1
fi

# Copy to Pi and then to Docker container
scp -q "$IMPORT_SCRIPT" ${PI_USER}@${PI_IP}:~/anagram-game/ || {
    echo -e "${RED}❌ Failed to copy import script${NC}"
    exit 1
}
ssh ${PI_USER}@${PI_IP} "docker cp ~/anagram-game/import-phrases.js anagram-game-server:/app/" || {
    echo -e "${RED}❌ Failed to copy import script to container${NC}"
    exit 1
}
echo -e "${GREEN}✅ Import script deployed${NC}"

# Step 6: Process each file
echo -e "${YELLOW}🔄 Processing imports...${NC}"
echo ""

TOTAL_IMPORTED=0
TOTAL_SKIPPED=0
SUCCESSFUL_FILES=()
FAILED_FILES=()

for PHRASE_FILE in "${PHRASE_FILES[@]}"; do
    FILENAME=$(basename "$PHRASE_FILE")
    echo -e "${BLUE}Processing: ${FILENAME}${NC}"
    
    # Copy file to Pi
    echo -e "  📤 Uploading..."
    scp -q "$PHRASE_FILE" ${PI_USER}@${PI_IP}:~/anagram-game/server/data/imported/ || {
        echo -e "  ${RED}❌ Failed to upload${NC}"
        FAILED_FILES+=("$FILENAME")
        continue
    }
    
    # Copy to Docker container
    ssh ${PI_USER}@${PI_IP} "docker cp ~/anagram-game/server/data/imported/${FILENAME} anagram-game-server:/app/data/" 2>/dev/null || {
        echo -e "  ${RED}❌ Failed to copy to container${NC}"
        FAILED_FILES+=("$FILENAME")
        continue
    }
    
    # Fix permissions
    ssh ${PI_USER}@${PI_IP} "docker exec -u root anagram-game-server chown nodejs:nodejs /app/data/${FILENAME}" 2>/dev/null
    
    # Run import
    echo -e "  🔄 Importing..."
    IMPORT_OUTPUT=$(ssh ${PI_USER}@${PI_IP} "docker exec -e DB_HOST=postgres -e DOCKER_ENV=true anagram-game-server node /app/import-phrases.js /app/data/${FILENAME} ${IMPORT_LIMIT}" 2>&1)
    
    # Check if import was successful
    if echo "$IMPORT_OUTPUT" | grep -q "Import Summary"; then
        # Extract numbers using sed instead of grep -P (for macOS compatibility)
        IMPORTED=$(echo "$IMPORT_OUTPUT" | sed -n 's/.*Imported: \([0-9]*\).*/\1/p' | head -1)
        SKIPPED=$(echo "$IMPORT_OUTPUT" | sed -n 's/.*Skipped: \([0-9]*\).*/\1/p' | head -1)
        
        # Default to 0 if extraction failed
        IMPORTED=${IMPORTED:-0}
        SKIPPED=${SKIPPED:-0}
        
        TOTAL_IMPORTED=$((TOTAL_IMPORTED + IMPORTED))
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + SKIPPED))
        
        echo -e "  ${GREEN}✅ Success: ${IMPORTED} imported, ${SKIPPED} skipped${NC}"
        SUCCESSFUL_FILES+=("$PHRASE_FILE")
        
        # Show batch import message if present
        if echo "$IMPORT_OUTPUT" | grep -q "Batch imported"; then
            BATCH_MSG=$(echo "$IMPORT_OUTPUT" | grep "Batch imported")
            echo -e "  ${GREEN}${BATCH_MSG}${NC}"
        fi
    else
        FAILED_FILES+=("$FILENAME")
        echo -e "  ${RED}❌ Import failed${NC}"
        # Show error details
        echo "$IMPORT_OUTPUT" | grep -E "Error|error|failed|Failed" | head -3 | sed 's/^/    /'
    fi
    
    # Clean up remote file after processing
    ssh ${PI_USER}@${PI_IP} "docker exec anagram-game-server rm -f /app/data/${FILENAME}" 2>/dev/null
    
    echo ""
done

# Step 7: Move successfully imported files to imported-on-stage directory
if [ ${#SUCCESSFUL_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}📦 Moving imported files to imported-on-stage...${NC}"
    
    # Find the project root directory (where import-phrases.js is located)
    PROJECT_ROOT=""
    if [ -f "import-phrases.js" ]; then
        PROJECT_ROOT="."
    elif [ -f "../import-phrases.js" ]; then
        PROJECT_ROOT=".."
    elif [ -f "../../import-phrases.js" ]; then
        PROJECT_ROOT="../.."
    else
        PROJECT_ROOT="." # fallback
    fi
    
    # Create imported-on-stage directory relative to project root
    IMPORTED_DIR="${PROJECT_ROOT}/server/data/imported/imported-on-stage"
    mkdir -p "$IMPORTED_DIR"
    
    # Move successfully imported files
    for FILE in "${SUCCESSFUL_FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        mv "$FILE" "$IMPORTED_DIR/" 2>/dev/null && \
            echo -e "  ✓ Moved: $FILENAME"
    done
    
    echo -e "${GREEN}✅ Files moved to: $IMPORTED_DIR${NC}"
    echo ""
fi

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎯 Import Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Total files processed: ${#PHRASE_FILES[@]}"
echo -e "  Successful imports: ${#SUCCESSFUL_FILES[@]}"
echo -e "  Failed imports: ${#FAILED_FILES[@]}"
echo -e "  ${GREEN}Total phrases imported: ${TOTAL_IMPORTED}${NC}"
echo -e "  ${YELLOW}Total phrases skipped: ${TOTAL_SKIPPED}${NC}"

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${RED}Failed files:${NC}"
    for file in "${FAILED_FILES[@]}"; do
        echo -e "    - $file"
    done
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Step 8: Verify database
echo ""
echo -e "${YELLOW}🔍 Verifying database...${NC}"
DB_COUNT=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-game-server node -e \"
const {Client} = require('pg');
const c = new Client({host:'postgres', database:'anagram_game', user:'postgres', password:'postgres'});
c.connect().then(async () => {
  const r = await c.query('SELECT COUNT(*) FROM phrases');
  console.log(r.rows[0].count);
  c.end();
}).catch(e => console.log('0'));
\"" 2>/dev/null || echo "0")

echo -e "${GREEN}✅ Total phrases in database: ${DB_COUNT}${NC}"

# Step 9: Test API endpoint
echo ""
echo -e "${YELLOW}🌐 Testing API access...${NC}"
API_STATUS=$(ssh ${PI_USER}@${PI_IP} "curl -s http://localhost:3000/api/status 2>/dev/null | grep -o '\"status\":\"[^\"]*\"' | cut -d'\"' -f4" || echo "failed")

if [ "$API_STATUS" == "healthy" ]; then
    echo -e "${GREEN}✅ API is healthy${NC}"
    
    # Get tunnel URL if available
    TUNNEL_URL=$(ssh ${PI_USER}@${PI_IP} "cat ~/cloudflare-tunnel-url.txt 2>/dev/null" || echo "")
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "${BLUE}🌍 Public URL: ${TUNNEL_URL}${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  API status: ${API_STATUS}${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Import process complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Build iOS apps: ./build_multi_sim.sh staging"
echo "  2. Test phrase retrieval in the app"
echo "  3. Monitor logs: ssh ${PI_USER}@${PI_IP} 'docker-compose -f ~/anagram-game/docker-compose.services.yml logs -f game-server'"