#!/bin/bash

# Interactive Phrase Generation and Preview Script
# 
# Usage: ./generate-and-preview.sh "RANGE:COUNT" [LANGUAGE] [THEME]
# Example: ./generate-and-preview.sh "0-50:15" en
# Example: ./generate-and-preview.sh "0-50:15" en gaming
# Example: ./generate-and-preview.sh "0-50:15" sv nature

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
    echo -e "${RED}❌ Usage: $0 \"RANGE:COUNT\" [LANGUAGE] [THEME]${NC}"
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 \"0-50:15\"             # 15 English phrases for difficulty 0-50"
    echo "  $0 \"0-50:15\" sv          # 15 Swedish phrases for difficulty 0-50"
    echo "  $0 \"51-100:20\" en gaming # 20 English gaming-themed phrases"
    echo "  $0 \"0-50:10\" sv nature   # 10 Swedish nature-themed phrases"
    exit 1
fi

RANGES="$1"
LANGUAGE="${2:-en}"
THEME="${3:-}"

echo "🎯 Interactive Phrase Generation"
echo "   Ranges: $RANGES"
echo "   Language: $LANGUAGE"
if [ -n "$THEME" ]; then
    echo "   Theme: $THEME"
fi
echo ""

# Step 1: Generate phrases (no import)
echo "📝 Step 1: Generating phrases..."

# Parse RANGES format "MIN-MAX:COUNT" into separate arguments
RANGE_PART=$(echo "$RANGES" | cut -d':' -f1)
COUNT_PART=$(echo "$RANGES" | cut -d':' -f2)

# Build command with optional theme parameter
COMMAND="node scripts/phrase-generator.js --range \"$RANGE_PART\" --count \"$COUNT_PART\" --language \"$LANGUAGE\""
if [ -n "$THEME" ]; then
    COMMAND="$COMMAND --theme \"$THEME\""
fi

eval $COMMAND

# Extract the generated file path from the generation
LATEST_GENERATED=$(ls -t ../data/phrases-sv-*-*.json 2>/dev/null | head -n 1)

# If no Swedish file found, look for any phrases file
if [ -z "$LATEST_GENERATED" ]; then
    LATEST_GENERATED=$(ls -t ../data/phrases-*.json 2>/dev/null | head -n 1)
fi

if [ ! -f "$LATEST_GENERATED" ]; then
    echo -e "${RED}❌ Error: Could not find generated phrases file${NC}"
    exit 1
fi

# Make the file path crystal clear
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}📁 GENERATED PHRASES FILE:${NC}"
echo -e "${CYAN}   $LATEST_GENERATED${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 2: Show table preview
echo -e "${YELLOW}📊 Step 2: Phrase Preview${NC}"
node scripts/preview-phrases.js --input "$LATEST_GENERATED" --format table

echo ""
echo -e "${BLUE}🎯 Next Steps - Your file is:${NC}"
echo -e "${CYAN}   $LATEST_GENERATED${NC}"
echo ""
echo -e "${GREEN}✅ Import to database:${NC}"
echo "   node scripts/phrase-importer.js --input \"$LATEST_GENERATED\" --import"
echo ""
echo -e "${YELLOW}🔄 Generate new batch:${NC}"
echo "   $0 \"RANGE:COUNT\" [LANGUAGE]"
echo ""
echo -e "${CYAN}📋 Other preview formats:${NC}"
echo "   node scripts/preview-phrases.js --input \"$LATEST_GENERATED\" --format detailed"
echo "   node scripts/preview-phrases.js --input \"$LATEST_GENERATED\" --format csv"
echo ""
echo -e "${BLUE}📄 View raw JSON data:${NC}"
echo "   cat \"$LATEST_GENERATED\""
echo ""
echo -e "${GREEN}💡 TIP: Your phrases are saved in the file path shown above${NC}"
echo ""

# Ask if user wants to import immediately
read -p "Import these phrases to database now? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}📥 Importing phrases to database...${NC}"
    node scripts/phrase-importer.js --input "$LATEST_GENERATED" --import
    echo -e "${GREEN}✅ Import completed!${NC}"
else
    echo -e "${YELLOW}⏸️  Import skipped. Use the commands above when ready.${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Session completed!${NC}"