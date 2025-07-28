#!/bin/bash

# Phrase Generation Master Script
# 
# Orchestrates the complete phrase generation workflow:
# 1. Generate phrases for specified difficulty ranges
# 2. Analyze phrases against difficulty algorithm
# 3. Import validated phrases to database
# 4. Generate comprehensive report

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
LOG_FILE="$DATA_DIR/generation-log-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "${RED}❌ Error: $1${NC}"
    exit 1
}

# Show help
show_help() {
    cat << EOF
🎯 Phrase Generation Master Script

Usage:
  ./generate-phrases.sh "RANGE1:COUNT[,RANGE2:COUNT,...]" [options]

Arguments:
  RANGE:COUNT    Difficulty range and count (e.g., "0-50:100")

Options:
  --language LANG     Language code (default: en)
  --dry-run          Simulate import without database changes
  --no-import        Generate and analyze only, skip import
  --clean-first      Clean duplicates before importing
  --help, -h         Show this help

Examples:
  ./generate-phrases.sh "0-50:100"                    # 100 easy phrases
  ./generate-phrases.sh "0-50:50,51-100:50"         # 50 easy, 50 medium
  ./generate-phrases.sh "200-250:25" --dry-run      # Test expert phrases
  ./generate-phrases.sh "101-150:100" --no-import   # Generate only

Workflow:
  1. 📝 Generate phrases for each specified range
  2. 🔍 Analyze phrases against difficulty algorithm  
  3. 📊 Filter high-quality phrases
  4. 📥 Import to database (unless --no-import)
  5. 📄 Generate comprehensive report

EOF
}

# Parse command line arguments
RANGES=""
LANGUAGE="en"
DRY_RUN=false
NO_IMPORT=false
CLEAN_FIRST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --language)
            LANGUAGE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-import)
            NO_IMPORT=true
            shift
            ;;
        --clean-first)
            CLEAN_FIRST=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$RANGES" ]]; then
                RANGES="$1"
            else
                error_exit "Unknown option: $1"
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$RANGES" ]]; then
    error_exit "Range specification is required. Use --help for usage information."
fi

# Create data directory
mkdir -p "$DATA_DIR"

# Start logging
log "${BLUE}🚀 Starting phrase generation workflow${NC}"
log "   Timestamp: $(date)"
log "   Ranges: $RANGES"
log "   Language: $LANGUAGE"
log "   Dry run: $DRY_RUN"
log "   No import: $NO_IMPORT"
log "   Clean first: $CLEAN_FIRST"
log "   Log file: $LOG_FILE"

# Validate Node.js scripts exist
for script in "phrase-generator.js" "phrase-analyzer.js" "phrase-importer.js"; do
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        error_exit "Required script not found: $script"
    fi
done

# Parse ranges and validate format
IFS=',' read -ra RANGE_ARRAY <<< "$RANGES"
TOTAL_PHRASES=0

for range_spec in "${RANGE_ARRAY[@]}"; do
    if [[ ! "$range_spec" =~ ^[0-9]+-[0-9]+:[0-9]+$ ]]; then
        error_exit "Invalid range format: $range_spec (expected: MIN-MAX:COUNT)"
    fi
    
    # Extract count and add to total
    count=$(echo "$range_spec" | cut -d':' -f2)
    TOTAL_PHRASES=$((TOTAL_PHRASES + count))
done

log "${BLUE}📊 Planning to generate $TOTAL_PHRASES total phrases across ${#RANGE_ARRAY[@]} ranges${NC}"

# Clean duplicates first if requested
if [[ "$CLEAN_FIRST" == true ]]; then
    log "${YELLOW}🧹 Cleaning existing duplicates...${NC}"
    if ! node "$SCRIPT_DIR/phrase-importer.js" --clean-duplicates --dry-run >> "$LOG_FILE" 2>&1; then
        error_exit "Failed to analyze duplicates"
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        if ! node "$SCRIPT_DIR/phrase-importer.js" --clean-duplicates >> "$LOG_FILE" 2>&1; then
            error_exit "Failed to clean duplicates"
        fi
    fi
fi

# Show initial database stats
log "${BLUE}📊 Current database statistics:${NC}"
node "$SCRIPT_DIR/phrase-importer.js" --stats 2>&1 | tee -a "$LOG_FILE"

# Generate phrases for each range
GENERATED_FILES=()
ANALYZED_FILES=()

for range_spec in "${RANGE_ARRAY[@]}"; do
    range=$(echo "$range_spec" | cut -d':' -f1)
    count=$(echo "$range_spec" | cut -d':' -f2)
    
    log "${YELLOW}📝 Generating $count phrases for range $range...${NC}"
    
    # Generate output filename with language and timestamp
    timestamp=$(date +%Y-%m-%dT%H-%M-%S)
    generated_file="$DATA_DIR/generated-${LANGUAGE}-${range}-${count}-${timestamp}.json"
    analyzed_file="$DATA_DIR/analyzed-${LANGUAGE}-${range}-${count}-${timestamp}.json"
    
    # Generate phrases
    log "   Running phrase generator..."
    if ! node "$SCRIPT_DIR/phrase-generator.js" \
        --range "$range" \
        --count "$count" \
        --language "$LANGUAGE" \
        --output "$generated_file" >> "$LOG_FILE" 2>&1; then
        error_exit "Failed to generate phrases for range $range"
    fi
    
    # Verify generation output
    if [[ ! -f "$generated_file" ]]; then
        error_exit "Generated file not found: $generated_file"
    fi
    
    GENERATED_FILES+=("$generated_file")
    
    # Analyze phrases
    log "   Running phrase analyzer..."
    if ! node "$SCRIPT_DIR/phrase-analyzer.js" \
        --input "$generated_file" \
        --output "$analyzed_file" \
        --target-range "$range" \
        --language "$LANGUAGE" \
        --filter >> "$LOG_FILE" 2>&1; then
        error_exit "Failed to analyze phrases for range $range"
    fi
    
    # Verify analysis output
    if [[ ! -f "$analyzed_file" ]]; then
        error_exit "Analyzed file not found: $analyzed_file"
    fi
    
    ANALYZED_FILES+=("$analyzed_file")
    
    log "${GREEN}✅ Completed processing for range $range${NC}"
done

# Combine all analyzed files if multiple ranges
FINAL_ANALYZED_FILE=""
if [[ ${#ANALYZED_FILES[@]} -eq 1 ]]; then
    FINAL_ANALYZED_FILE="${ANALYZED_FILES[0]}"
else
    # Combine multiple files
    FINAL_ANALYZED_FILE="$DATA_DIR/combined-analyzed-$(date +%Y%m%d-%H%M%S).json"
    log "${YELLOW}🔄 Combining ${#ANALYZED_FILES[@]} analyzed files...${NC}"
    
    # Create combined file
    echo '{' > "$FINAL_ANALYZED_FILE"
    echo '  "metadata": {' >> "$FINAL_ANALYZED_FILE"
    echo "    \"combined_at\": \"$(date -Iseconds)\"," >> "$FINAL_ANALYZED_FILE"
    echo "    \"source_files\": [" >> "$FINAL_ANALYZED_FILE"
    
    for i in "${!ANALYZED_FILES[@]}"; do
        echo -n "      \"$(basename "${ANALYZED_FILES[$i]}")\"" >> "$FINAL_ANALYZED_FILE"
        if [[ $i -lt $((${#ANALYZED_FILES[@]} - 1)) ]]; then
            echo "," >> "$FINAL_ANALYZED_FILE"
        else
            echo "" >> "$FINAL_ANALYZED_FILE"
        fi
    done
    
    echo '    ],' >> "$FINAL_ANALYZED_FILE"
    echo "    \"language\": \"$LANGUAGE\"," >> "$FINAL_ANALYZED_FILE"
    echo "    \"total_files\": ${#ANALYZED_FILES[@]}" >> "$FINAL_ANALYZED_FILE"
    echo '  },' >> "$FINAL_ANALYZED_FILE"
    echo '  "phrases": [' >> "$FINAL_ANALYZED_FILE"
    
    # Combine phrases from all files
    first_file=true
    for analyzed_file in "${ANALYZED_FILES[@]}"; do
        if [[ "$first_file" != true ]]; then
            echo "," >> "$FINAL_ANALYZED_FILE"
        fi
        first_file=false
        
        # Extract phrases array from each file
        jq -r '.phrases[] | @json' "$analyzed_file" | while read -r phrase; do
            echo "    $phrase" >> "$FINAL_ANALYZED_FILE"
        done
    done
    
    echo '' >> "$FINAL_ANALYZED_FILE"
    echo '  ]' >> "$FINAL_ANALYZED_FILE"
    echo '}' >> "$FINAL_ANALYZED_FILE"
    
    log "${GREEN}✅ Combined file created: $FINAL_ANALYZED_FILE${NC}"
fi

# Import phrases unless --no-import is specified
IMPORT_RESULTS=""
if [[ "$NO_IMPORT" != true ]]; then
    log "${YELLOW}📥 Importing phrases to database...${NC}"
    
    import_args="--input $FINAL_ANALYZED_FILE"
    if [[ "$DRY_RUN" == true ]]; then
        import_args="$import_args --dry-run"
    else
        import_args="$import_args --import"
    fi
    
    # Generate import report filename
    IMPORT_REPORT="$DATA_DIR/import-report-$(date +%Y%m%d-%H%M%S).json"
    import_args="$import_args --output $IMPORT_REPORT"
    
    if ! node "$SCRIPT_DIR/phrase-importer.js" $import_args >> "$LOG_FILE" 2>&1; then
        error_exit "Failed to import phrases"
    fi
    
    IMPORT_RESULTS="$IMPORT_REPORT"
    log "${GREEN}✅ Import completed: $IMPORT_REPORT${NC}"
else
    log "${YELLOW}⏭️  Skipping import (--no-import specified)${NC}"
fi

# Show final database stats
log "${BLUE}📊 Final database statistics:${NC}"
node "$SCRIPT_DIR/phrase-importer.js" --stats 2>&1 | tee -a "$LOG_FILE"

# Generate comprehensive report
FINAL_REPORT="$DATA_DIR/generation-report-$(date +%Y%m%d-%H%M%S).json"
log "${YELLOW}📄 Generating final report...${NC}"

cat > "$FINAL_REPORT" << EOF
{
  "workflow": {
    "timestamp": "$(date -Iseconds)",
    "ranges": "$RANGES",
    "language": "$LANGUAGE",
    "dry_run": $DRY_RUN,
    "no_import": $NO_IMPORT,
    "clean_first": $CLEAN_FIRST,
    "total_requested_phrases": $TOTAL_PHRASES,
    "ranges_processed": ${#RANGE_ARRAY[@]}
  },
  "files": {
    "log_file": "$LOG_FILE",
    "generated_files": [$(printf '"%s",' "${GENERATED_FILES[@]}" | sed 's/,$//')],
    "analyzed_files": [$(printf '"%s",' "${ANALYZED_FILES[@]}" | sed 's/,$//')],
    "final_analyzed_file": "$FINAL_ANALYZED_FILE"$(if [[ -n "$IMPORT_RESULTS" ]]; then echo ","; echo "    \"import_report\": \"$IMPORT_RESULTS\""; fi)
  },
  "generated_at": "$(date -Iseconds)",
  "version": "1.0.0"
}
EOF

# Display summary
log "${GREEN}🎉 Phrase generation workflow completed!${NC}"
log ""
log "${BLUE}📋 Summary:${NC}"
log "   Ranges processed: ${#RANGE_ARRAY[@]}"
log "   Total requested: $TOTAL_PHRASES phrases"
log "   Generated files: ${#GENERATED_FILES[@]}"
log "   Analyzed files: ${#ANALYZED_FILES[@]}"
log "   Final analyzed file: $FINAL_ANALYZED_FILE"
if [[ -n "$IMPORT_RESULTS" ]]; then
    log "   Import report: $IMPORT_RESULTS"
fi
log "   Final report: $FINAL_REPORT"
log "   Log file: $LOG_FILE"
log ""
log "${BLUE}📚 Next Steps:${NC}"
if [[ "$DRY_RUN" == true ]]; then
    log "   • Review dry-run results in log file"
    log "   • Run without --dry-run to perform actual import"
elif [[ "$NO_IMPORT" == true ]]; then
    log "   • Review analyzed phrases in: $FINAL_ANALYZED_FILE"
    log "   • Import manually: node phrase-importer.js --input $FINAL_ANALYZED_FILE --import"
else
    log "   • Check database statistics: node phrase-importer.js --stats"
    log "   • Review import report: $IMPORT_RESULTS"
fi

log "   • View detailed logs: cat $LOG_FILE"
log ""
log "${GREEN}✅ Workflow completed successfully!${NC}"