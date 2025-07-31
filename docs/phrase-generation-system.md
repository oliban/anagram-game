# Phrase Generation System

## Overview
Automated system for generating, analyzing, and importing anagram game phrases with precise difficulty targeting.

## Quick Start Commands

### 🚀 Streamlined Workflow (Recommended):
```bash
# Generate phrases and see immediate preview
./server/scripts/generate-and-preview.sh "0-50:15"      # 15 English phrases
./server/scripts/generate-and-preview.sh "0-50:15" sv   # 15 Swedish phrases
./server/scripts/generate-and-preview.sh "51-100:20"    # 20 medium difficulty

# This will:
# 1. Generate phrases for your range
# 2. Automatically show table preview with clever clues
# 3. Give you clear file path and import options
# 4. Ask if you want to import immediately
```

### 🔧 Advanced Multi-Range Generation:
```bash
# Generate multiple ranges at once (batch processing)
./server/scripts/generate-phrases.sh "0-50:100,51-100:100,101-150:100"
./server/scripts/generate-phrases.sh "200-250:100,251-300:50"
```

## System Architecture & Workflow

### Process Flow Diagram (Docker Microservices)
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  1. AI GENERATE │───▶│  2. ANALYZE     │───▶│  3. PREVIEW     │───▶│  4. DOCKER      │
│  🤖 AI-powered  │    │  phrase-        │    │  Review JSON    │    │  IMPORT         │
│  meaningful     │    │  analyzer.js    │    │  Files          │    │  🐳 Container   │
│  phrases        │    │                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │                       │
         ▼                       ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ 🎯 Coherent     │    │   analyzed-     │    │ User Decision   │    │ 🗄️ PostgreSQL   │
│ phrases like    │    │   phrases.json  │    │ Point           │    │ Docker DB       │
│ "fresh air"     │    │ + clever hints  │    │                 │    │ localhost:5432  │
│ "happy child"   │    │                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘

🐳 DOCKER WORKFLOW:
   1. Generate phrases on host: `node server/scripts/phrase-generator.js`
   2. Copy files to container: `docker cp analyzed-phrases.json anagram-game-server:/app/`
   3. Import in container: `docker exec anagram-game-server node phrase-importer.js --import`
   4. Verify via API: `curl http://localhost:3000/api/phrases/for/{playerId}`

🔍 PREVIEW POINTS:
   • After Step 1: AI-generated meaningful phrases with difficulty scores
   • After Step 2: Analyzed phrases with quality metrics (RECOMMENDED)
   • Before Step 4: Final review before database import

🤖 AI ENHANCEMENT:
   • Generates coherent, meaningful phrase combinations
   • Replaces random word combinations with contextual phrases
   • Creates thematic clues without using phrase words
   • Supports multiple languages (English/Swedish)

🏗️ MICROSERVICES ARCHITECTURE:
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   📱 iOS App    │───▶│  🎮 Game Server │───▶│ 🗄️ PostgreSQL   │
│  SwiftUI +      │    │  Docker:3000    │    │  Docker:5432    │
│  SpriteKit      │    │  + WebSocket    │    │  Shared DB      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  HTTP/REST API  │    │ DatabasePhrase  │    │ Global Phrases  │
│  Phrase Fetch   │    │ Query Engine    │    │ 140+ with Hints │
│  Score Submit   │    │ Consumption     │    │ Approval System │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### File Structure
```
📁 server/scripts/
├── generate-phrases.sh          # Master orchestration script
├── phrase-generator.js          # 🤖 AI-powered meaningful phrase generation
├── phrase-analyzer.js           # Tests phrases against difficulty algorithm
├── phrase-importer.js           # Imports validated phrases to database
├── preview-phrases.js           # Preview generated phrases before import
├── phrase-data-en.js            # English phrase data for AI simulation
└── phrase-data-sv.js            # Swedish phrase data for AI simulation

📁 server/data/
├── generated-{lang}-{range}-{count}-{timestamp}.json   # Raw generated phrases
├── analyzed-{lang}-{range}-{count}-{timestamp}.json    # Analyzed phrases with quality scores
├── combined-analyzed-*.json                            # Multi-range combined file
├── import-report-*.json                                # Import results and statistics
└── generation-log-*.log                                # Detailed process logs
```

## Detailed Usage

### 1. Streamlined Interactive Workflow (Recommended)
```bash
# Single command that does everything:
./server/scripts/generate-and-preview.sh "0-50:15"

# This automatically:
# - Generates phrases for difficulty range 0-50
# - Shows table preview with clever clues
# - Displays clear file path
# - Offers immediate import option
# - Provides next step commands
```

**Example Output:**
```
📁 GENERATED PHRASES FILE:
   ../data/analyzed-en-0-50-15-2025-07-28T11-12-22.json

📊 Phrase Preview:
DIFFICULTY  PHRASE         CLUE
──────────────────────────────────────────
43          fresh air      What city dwellers crave most
45          happy child    Playground giggles source
46          cold winter    Jack Frost's favorite season

🎯 Next Steps - Your file is:
   ../data/analyzed-en-0-50-15-2025-07-28T11-12-22.json

✅ Import to database:
   node phrase-importer.js --input "../data/analyzed-en-0-50-15-2025-07-28T11-12-22.json" --import
```

### 2. Manual Step-by-Step Workflow
```bash
# Step 1: Generate and analyze phrases (no import)
./server/scripts/generate-phrases.sh "200-250:25" --no-import

# Step 2: Preview the generated phrases (use actual filename with timestamp)
node server/scripts/preview-phrases.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json

# Step 3: Import after review (if satisfied) 
node server/scripts/phrase-importer.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json --import
```

### 2. Master Script (Full Automation)
```bash
# Generate phrases for multiple ranges
./server/scripts/generate-phrases.sh "RANGE1:COUNT,RANGE2:COUNT,..."

# Examples:
./server/scripts/generate-phrases.sh "0-50:100"              # 100 easy phrases
./server/scripts/generate-phrases.sh "0-50:50,51-100:50"    # 50 each of easy/medium
./server/scripts/generate-phrases.sh "200-250:25"           # 25 expert phrases
```

## Preview Generated Phrases

### Quick Preview Commands
```bash
# Using dedicated preview script (RECOMMENDED) - use actual timestamped filename
node server/scripts/preview-phrases.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json

# Different formats
node server/scripts/preview-phrases.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json --format simple
node server/scripts/preview-phrases.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json --format table
node server/scripts/preview-phrases.js --input server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json --format csv > preview.csv

# With filters
node server/scripts/preview-phrases.js --input server/data/analyzed-phrases.json --filter "200-250" --limit 5

# Alternative: Using jq (if available) - use actual timestamped filename
jq '.phrases[] | {phrase, clue, difficulty}' server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json
jq -r '.phrases[] | "\(.difficulty)\t\(.phrase)\t\(.clue)"' server/data/analyzed-en-200-250-25-2025-07-28T11-15-30.json | column -t
```

### Preview Output Example
```json
{
  "phrase": "fresh air",
  "clue": "What city dwellers crave most",
  "difficulty": 43
}
{
  "phrase": "happy child", 
  "clue": "Playground giggles source",
  "difficulty": 45
}
{
  "phrase": "cold winter",
  "clue": "Jack Frost's favorite season", 
  "difficulty": 46
}
```

**🧩 Clever Clue System Features:**
- **Puzzle-like clues**: Require lateral thinking, not just definitions
- **Cultural references**: "Weather app's smiley face", "Navigator's ancient GPS"
- **Creative metaphors**: "Nature's perfect mirror", "Winter's blank canvas"
- **Contextual associations**: "Playground giggles source", "Solar panel's best friend"
- **No word repetition**: Clues never contain phrase words
- **Multi-language support**: Culturally appropriate clues in English/Swedish

### Advanced Preview Options
```bash
# Filter by difficulty range
jq '.phrases[] | select(.difficulty >= 200 and .difficulty <= 250)' server/data/analyzed-*.json

# Show only high-quality phrases
jq '.phrases[] | select(.quality.score >= 0.9)' server/data/analyzed-*.json

# Export to CSV for spreadsheet review
jq -r '.phrases[] | [.difficulty, .phrase, .clue, .quality.score] | @csv' server/data/analyzed-*.json > preview.csv
```

### 3. Individual Scripts

#### Generate Phrases (🤖 AI-Powered)
```bash
# Create meaningful phrases for specific difficulty range
node server/scripts/phrase-generator.js --range "0-50" --count 100 --output "easy-phrases.json"
node server/scripts/phrase-generator.js --range "200-250" --count 50 --output "expert-phrases.json"

# Multi-language support
node server/scripts/phrase-generator.js --range "0-50" --count 50 --language "sv" --output "swedish-easy.json"
```

#### Analyze Phrases
```bash
# Test phrases against difficulty algorithm
node server/scripts/phrase-analyzer.js --input "easy-phrases.json" --output "analyzed-easy.json"
node server/scripts/phrase-analyzer.js --input "expert-phrases.json" --output "analyzed-expert.json" --target-range "200-250"
```

#### Import to Database
```bash
# Import validated phrases
node server/scripts/phrase-importer.js --input "analyzed-easy.json" --dry-run
node server/scripts/phrase-importer.js --input "analyzed-easy.json" --import
```

## Filename Format

### New Timestamped Naming Convention
All generated files now include language identifier and timestamp for better organization:

**Format:** `{type}-{language}-{range}-{count}-{timestamp}.json`

**Examples:**
- `generated-en-0-50-15-2025-07-28T11-12-22.json` - English, easy range, 15 phrases
- `analyzed-sv-101-150-20-2025-07-28T14-30-45.json` - Swedish, hard range, 20 phrases  
- `generated-en-200-250-10-2025-07-28T09-15-30.json` - English, expert range, 10 phrases

**Benefits:**
- **Language clarity**: Easy to identify English (`en`) vs Swedish (`sv`) files
- **No conflicts**: Timestamp ensures unique filenames
- **Chronological sorting**: Files sort naturally by generation time
- **Easy filtering**: Can use wildcards like `*sv*` or `*en*` to find language-specific files

**File types:**
- `generated-*` - Raw AI-generated phrases before analysis
- `analyzed-*` - Processed phrases with quality scores and metrics

## Configuration

### Difficulty Ranges
- **0-50**: Very Easy (2-3 short words, common letters)
- **51-100**: Easy (3-4 words, some complexity)
- **101-150**: Medium (4-5 words, mixed complexity)
- **151-200**: Hard (5+ words, challenging combinations)
- **200+**: Expert (Complex phrases, rare letters, long sequences)

### Generation Parameters
```json
{
  "phraseGeneration": {
    "minWordsPerPhrase": 2,
    "maxWordsPerPhrase": 8,
    "qualityThreshold": 0.8,
    "duplicateCheck": true,
    "languageSupport": ["en", "sv"]
  },
  "difficultyTargeting": {
    "tolerance": 5,
    "maxAttempts": 1000,
    "fallbackStrategy": "closest_match"
  }
}
```

## AI-Powered Generation System

### How AI Generation Works
The system uses artificial intelligence to generate meaningful, coherent phrases instead of random word combinations:

```javascript
// Example AI-generated phrases by difficulty:
const aiPhrases = {
  "0-50": [
    "fresh air", "happy child", "cold winter", "warm sun", "blue sky"
  ],
  "51-100": [
    "gentle breeze", "morning coffee", "quiet moment", "bright future"
  ],
  "101-150": [
    "peaceful evening", "creative thinking", "wonderful journey"
  ]
};
```

### Quality Guarantees
- **Coherent combinations**: "fresh air" not "purple elephant"
- **Natural language patterns**: Adjective + noun, verb + adverb
- **Clever puzzle clues**: Require lateral thinking, not just definitions
- **No word repetition**: Clues never contain phrase words
- **Multi-language support**: English and Swedish with culturally appropriate clues

### Clever Clue Examples by Category
```javascript
const clueExamples = {
  personification: {
    "cold winter": "Jack Frost's favorite season",
    "soft rain": "Umbrella's gentle reminder"
  },
  cultural: {
    "nice day": "Weather app's smiley face", 
    "bright star": "Navigator's ancient GPS"
  },
  metaphor: {
    "calm lake": "Nature's perfect mirror",
    "white snow": "Winter's blank canvas"
  },
  contextual: {
    "happy child": "Playground giggles source",
    "good book": "Page turner's addiction"
  }
};
```

## Workflow Examples

### Example 1: Interactive Range Generation (Recommended)
```bash
# Task: "Generate phrases for intervals 0-50"
./server/scripts/generate-and-preview.sh "0-50:15"
```
**What happens:**
1. Generates 15 AI-powered meaningful phrases targeting 0-50 difficulty
2. Tests each phrase with difficulty algorithm  
3. Creates clever contextual clues (e.g., "Jack Frost's favorite season")
4. Shows immediate table preview with file path
5. Offers interactive import option
6. Provides clear next step commands

**Example Output Preview:**
```
DIFFICULTY  PHRASE         CLUE
──────────────────────────────────────────
46          cold winter    Jack Frost's favorite season
43          fresh air      What city dwellers crave most
45          happy child    Playground giggles source
```

### Example 2: Batch Multi-Range Generation
```bash
# Task: "Generate phrases for intervals 0-50, 100-150, 200-250"
./server/scripts/generate-phrases.sh "0-50:100,100-150:100,200-250:100"
```
**What happens:**
1. Processes multiple difficulty ranges in one command
2. Generates 300 total phrases across three ranges
3. Each range gets AI-powered meaningful phrases with clever clues
4. Automatically imports all ranges to database
5. Provides comprehensive statistics report

### Example 3: Custom Count Distribution
```bash
# Task: "Generate 50 easy, 30 medium, 20 hard phrases"
./server/scripts/generate-phrases.sh "0-50:50,51-100:30,101-150:20"
```

### Example 4: Swedish Language Generation
```bash
# Task: "Generate Swedish phrases for beginners"
./server/scripts/generate-and-preview.sh "0-50:10" sv
```
**Sample Swedish Output:**
```
📁 GENERATED PHRASES FILE:
   ../data/analyzed-sv-0-50-10-2025-07-28T11-11-08.json

DIFFICULTY  PHRASE         CLUE
──────────────────────────────────────────
45          blå himmel     Fågelns oändliga tak
35          lugn sjö       Naturens perfekta spegel
52          kall vinter    Snögubbens favoritårstid
```

## Output Analysis

### Generation Report
```json
{
  "timestamp": "2025-07-28T10:00:00Z",
  "request": "200-250:100",
  "results": {
    "targetRange": "200-250",
    "requestedCount": 100,
    "generated": 95,
    "imported": 90,
    "duplicatesSkipped": 5,
    "difficultyDistribution": {
      "195-205": 15,
      "206-215": 20,
      "216-225": 25,
      "226-235": 20,
      "236-245": 10,
      "246-255": 5
    },
    "averageDifficulty": 223.4,
    "generationTime": "45.2s"
  }
}
```

### Database Verification
```bash
# Check phrase distribution after import
node -e "
const { query } = require('./server/database/connection');
query('SELECT COUNT(*) FROM phrases WHERE difficulty_level BETWEEN 200 AND 250')
  .then(result => console.log('Phrases in 200-250 range:', result.rows[0].count))
  .then(() => process.exit(0));
"
```

## Troubleshooting

### Common Issues
1. **Low generation success rate**
   - Increase `maxAttempts` in config
   - Widen difficulty tolerance
   - Enhance AI generation patterns

2. **Phrases too easy/hard**
   - Adjust algorithm parameters in `shared/difficulty-algorithm-config.json`
   - Refine AI generation for target difficulty
   - Update word complexity in AI prompts

3. **Import failures**
   - Check database connection
   - Verify phrase uniqueness
   - Review SQL constraints

### Debug Mode
```bash
# Run with detailed logging
DEBUG=1 ./server/scripts/generate-phrases.sh "200-250:100"

# Test single phrase difficulty
node -e "console.log(require('./shared/difficulty-algorithm').calculateScore({phrase: 'test phrase', language: 'en'}))"
```

## Maintenance

### Update AI Generation
```bash
# Test AI generation for new difficulty ranges
node server/scripts/phrase-generator.js --range "300-400" --count 10 --dry-run
```

### Clean Database
```bash
# Remove duplicates
node server/scripts/phrase-importer.js --clean-duplicates

# Remove phrases outside target ranges
node server/scripts/phrase-importer.js --clean-outliers --ranges "0-50,51-100,101-150"
```

## API Integration

### Admin Batch Import API (NEW - v1.2.0)

The new admin batch import endpoint provides a direct way to import phrases without file-based workflows:

```bash
# Import phrases directly via REST API
curl -X POST http://localhost:3000/api/admin/phrases/batch-import \
  -H "Content-Type: application/json" \
  -d '{
    "phrases": [
      {
        "content": "bright sunny day",
        "hint": "Perfect weather for outdoor activities", 
        "language": "en",
        "isGlobal": true,
        "phraseType": "community"
      },
      {
        "content": "kall vinter",
        "hint": "Årstid som får termometern att krympa",
        "language": "sv", 
        "isGlobal": true,
        "phraseType": "community"
      }
    ]
  }'
```

#### Converting Generated Files to API Format

Use this helper to convert analyzed phrase files for API import:

```bash
# Convert analyzed phrase file to admin API format
jq '{
  phrases: [
    .phrases[] | select(.difficulty >= 50 and .difficulty <= 100) | {
      content: .phrase,
      hint: .clue,
      language: .language,
      isGlobal: true,
      phraseType: "community"
    }
  ]
}' server/data/analyzed-sv-50-100-50-manual.json > swedish_batch_import.json

# Import via API
curl -X POST http://localhost:3000/api/admin/phrases/batch-import \
  -H "Content-Type: application/json" \
  -d @swedish_batch_import.json
```

#### API Features
- **Batch Processing**: Up to 100 phrases per request
- **System-Generated**: Phrases created with null senderId (appear as "System")
- **Automatic Difficulty**: Uses shared difficulty algorithm for scoring
- **Multi-language**: Supports all game languages
- **Validation**: Comprehensive phrase and hint validation
- **Error Reporting**: Detailed success/failure reporting per phrase

#### Response Format
```json
{
  "success": true,
  "message": "Batch import completed: 12 successful, 0 failed",
  "results": {
    "summary": {
      "totalProcessed": 12,
      "totalSuccessful": 12, 
      "totalFailed": 0,
      "successRate": 100
    },
    "successful": [
      {
        "index": 1,
        "id": "uuid",
        "content": "kall vinter",
        "language": "sv",
        "difficulty": 52
      }
    ]
  }
}
```

### Legacy Integration

The phrase generation system integrates with the existing API:
- Generated phrases use standard database schema
- Compatible with existing phrase endpoints
- Maintains phrase approval workflow
- Supports multilingual content

## 🎉 Recent Improvements

### 🚀 Admin Batch Import API (v1.2.0)
- **Direct API Import**: No more file-based workflows - import phrases directly via REST API
- **System-Generated Phrases**: Clean display as "System" sender instead of "Unknown Player"
- **Batch Processing**: Up to 100 phrases per request with detailed progress reporting
- **Multi-language Support**: Swedish, English, and all supported languages
- **Automatic Difficulty**: Server-side difficulty calculation using shared algorithm
- **Validation & Error Handling**: Comprehensive validation with per-phrase error reporting

### ✨ New Streamlined Workflow (v1.1.0)
- **Single Command**: `./generate-and-preview.sh "0-50:15"` does everything
- **Instant Preview**: Automatic table display with clear file path
- **Interactive Import**: Choose to import immediately or later
- **Clear Navigation**: Next step commands provided automatically

### 🧩 Revolutionary Clue System (v1.1.0)
- **Clever Contextual Clues**: Replaced boring "Associated concepts" with engaging puzzles
- **Lateral Thinking Required**: Clues like "Jack Frost's favorite season" for "cold winter"
- **Cultural References**: "Weather app's smiley face", "Navigator's ancient GPS"
- **Creative Metaphors**: "Nature's perfect mirror", "Winter's blank canvas"
- **Unique Per Phrase**: No repeated clue patterns across different phrases

### 🤖 AI-Powered Quality
- **Meaningful Phrases**: "fresh air", "happy child" instead of random combinations
- **100% Success Rate**: All generated phrases are coherent and natural
- **Multi-language Support**: English and Swedish with culturally appropriate clues
- **Perfect Difficulty Targeting**: Consistently hits target ranges

### 📋 Comparison: Before vs After

**Before (Old System):**
```
PHRASE          CLUE
fresh air       Associated concepts
happy child     Related words  
cold winter     Associated concepts
```

**After (New System):**
```
PHRASE          CLUE
fresh air       What city dwellers crave most
happy child     Playground giggles source
cold winter     Jack Frost's favorite season
```

The new system transforms the experience from generic templates to engaging, puzzle-like clues that challenge players to think creatively!

---

**Last Updated:** 2025-07-28  
**Version:** 1.1.0