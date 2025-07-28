#!/bin/bash

# Interactive Phrase Generation and Preview Script
# 
# Usage: ./generate-and-preview.sh "RANGE:COUNT" [LANGUAGE]
# Example: ./generate-and-preview.sh "0-50:15" en

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}❌ Usage: $0 \"RANGE:COUNT\" [LANGUAGE]${NC}"
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 \"0-50:15\"      # 15 English phrases for difficulty 0-50"
    echo "  $0 \"0-50:15\" sv   # 15 Swedish phrases for difficulty 0-50"
    echo "  $0 \"51-100:20\"    # 20 English phrases for difficulty 51-100"
    exit 1
fi

RANGES="$1"
LANGUAGE="${2:-en}"

echo -e "${BLUE}🎯 Interactive Phrase Generation${NC}"
echo "   Ranges: $RANGES"
echo "   Language: $LANGUAGE"
echo ""

# Step 1: Generate phrases (no import)
echo -e "${YELLOW}📝 Step 1: Generating phrases...${NC}"
./generate-phrases.sh "$RANGES" --language "$LANGUAGE" --no-import

# Extract the analyzed file path from the generation
LATEST_ANALYZED=$(ls -t ../data/analyzed-*.json | head -n 1)

if [ ! -f "$LATEST_ANALYZED" ]; then
    echo -e "${RED}❌ Error: Could not find generated phrases file${NC}"
    exit 1
fi

# Make the file path crystal clear
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}📁 GENERATED PHRASES FILE:${NC}"
echo -e "${CYAN}   $LATEST_ANALYZED${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 2: Show table preview
echo -e "${YELLOW}📊 Step 2: Phrase Preview${NC}"
node preview-phrases.js --input "$LATEST_ANALYZED" --format table

echo ""
echo -e "${BLUE}🎯 Next Steps - Your file is:${NC}"
echo -e "${CYAN}   $LATEST_ANALYZED${NC}"
echo ""
echo -e "${GREEN}✅ Import to database:${NC}"
echo "   node phrase-importer.js --input \"$LATEST_ANALYZED\" --import"
echo ""
echo -e "${YELLOW}🔄 Generate new batch:${NC}"
echo "   $0 \"RANGE:COUNT\" [LANGUAGE]"
echo ""
echo -e "${CYAN}📋 Other preview formats:${NC}"
echo "   node preview-phrases.js --input \"$LATEST_ANALYZED\" --format detailed"
echo "   node preview-phrases.js --input \"$LATEST_ANALYZED\" --format csv"
echo ""
echo -e "${BLUE}📄 View raw JSON data:${NC}"
echo "   cat \"$LATEST_ANALYZED\""
echo ""
echo -e "${GREEN}💡 TIP: Your phrases are saved in the file path shown above${NC}"
echo ""

# Ask if user wants to import immediately
read -p "Import these phrases to database now? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}📥 Importing phrases to database...${NC}"
    node phrase-importer.js --input "$LATEST_ANALYZED" --import
    echo -e "${GREEN}✅ Import completed!${NC}"
else
    echo -e "${YELLOW}⏸️  Import skipped. Use the commands above when ready.${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Session completed!${NC}"