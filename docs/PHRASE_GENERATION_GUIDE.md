# Phrase Generation Guide

## Complete Workflow for AI-Generated Phrases

### Working Directory Context
**CRITICAL**: Commands must be run from specific directories:
- **Generation script**: Run from PROJECT ROOT - `cd server && node scripts/phrase-generator.js`
- **Import script**: Run from PROJECT ROOT - `node server/scripts/phrase-importer.js` 
- **Deployment scripts**: Run from PROJECT ROOT
- **Docker commands**: Run from PROJECT ROOT
- **Database files**: Located in `server/data/` directory

**🚨 PATH ERRORS**: If you get "Cannot find module" errors, you're in the wrong directory!

### Quick Commands

#### Complete Phrase Generation Workflow
```bash
# Step 1: Generate phrases (CLAUDE IS THE AI - generate directly)
# If using script: cd server && node scripts/phrase-generator.js --range 50-150 --count 50 --language sv --theme winter
# If script fails: CLAUDE generates phrases directly and creates JSON file

# Step 2: MANDATORY - Present phrases to user in table format
# ⚠️ CRITICAL: PRESENT GENERATED PHRASES TO USER IN TABLE FORMAT
# ⚠️ CRITICAL: WAIT FOR EXPLICIT USER APPROVAL BEFORE ANY IMPORTS

# Step 3: Create JSON file (if missing)
# Create server/data/imported/YYYY-MM-DD-theme-phrases-LANG-MIN-MAX-COUNT.json

# Step 4: Ask about local import (optional)
# ONLY AFTER USER APPROVAL:
# node server/scripts/phrase-importer.js --input server/data/phrases-sv-*.json --import

# Step 5: MANDATORY - Run phrase count analysis after import
# 🚨 MANDATORY: Always run after successful import
# node server/phrase-count-detailed.js

# Step 6: Ask separately about staging import 
# 🚨 MANDATORY: Ask "Do you want to import these to staging?"
# 🚨 WAIT FOR EXPLICIT USER APPROVAL
# ONLY AFTER USER SAYS YES:
# bash scripts/import-phrases-staging.sh server/data/imported/filename.json
```

#### Staging Import (Docker Environment)

**Automated Script (Recommended):**
```bash
# Single command to import phrases to staging
./scripts/import-phrases-staging.sh server/data/imported/phrases-sv.json

# With options:
./scripts/import-phrases-staging.sh server/data/imported/phrases-en.json --deploy --limit 100
```

**Manual Steps (if needed):**
```bash
# 1. Deploy system to staging (if not already done):
bash Scripts/deploy-to-pi.sh

# 2. Copy import script and phrase files to Pi:
scp import-phrases.js pi@192.168.1.222:~/anagram-game/
scp server/data/imported/*.json pi@192.168.1.222:~/anagram-game/server/data/imported/

# 3. Copy files into Docker container:
ssh pi@192.168.1.222 "docker cp ~/anagram-game/import-phrases.js anagram-game-server:/app/"
ssh pi@192.168.1.222 "docker cp ~/anagram-game/server/data/imported/ anagram-game-server:/app/data/"

# 4. Fix permissions in container:
ssh pi@192.168.1.222 "docker exec -u root anagram-game-server chown -R nodejs:nodejs /app/data"

# 5. Run import inside Docker container:
ssh pi@192.168.1.222 "docker exec -e DB_HOST=postgres -e DOCKER_ENV=true anagram-game-server node /app/import-phrases.js /app/data/YOUR-FILE.json"

# Note: The import script auto-detects Docker environment and uses correct database host
```

### Critical Path Corrections
- **Phrase generation**: `cd server && node scripts/phrase-generator.js` (must cd to server directory first)
- **Phrase import**: `cd server && node scripts/phrase-importer.js` (must cd to server first)  
- **Staging deploy**: `./scripts/deploy-staging.sh` (from project root)
- **Working directory matters** - commands fail if run from wrong directory!
- **🚨 MANDATORY**: Always present phrases to user in table format and get approval before importing

## 8-Step Process Flow (WITH MANDATORY USER APPROVAL)

### 1. Entry Point
`phrase-generator.js` → `ai-phrase-generator.js`

### 2. Overgeneration Strategy
- **Request 10** → **Generate 40 candidates** (4x quality buffer)
- Provides selection flexibility
- Ensures quality through abundance

### 3. AI Processing
- **Generate** initial phrases
- **Fix Swedish grammar** using language rules
- **Select best 10** WITH PROPER DIFFICULTY DISTRIBUTION

### 4. Difficulty Scoring
- Each phrase scored using `shared/difficulty-algorithm`
- Consistent scoring across iOS and server
- Algorithm considers word complexity, length, patterns

### 5. Validation Rules
- **Word length**: ≤7 characters per word
- **Word count**: 2-4 words per phrase
- **Theme relevance**: Must match requested theme with SPECIFIC CONTENT
  - ❌ **NOT generic terms**: "roman", "dikt", "författare" (too generic)
  - ✅ **SPECIFIC CONTENT**: "Selma Lagerlöf", "Röda rummet", "Gösta Berling" (actual works/authors)
  - ✅ **REAL REFERENCES**: Authors, book titles, character names, historical works
- **🚨 CRITICAL: Perfect grammar validation - BOTH phrases AND clues**
  - **Swedish phrases**: Correct possessive forms, compound words, no särskrivning
  - **Swedish clues**: Proper word order, grammatical completeness, correct articles
  - **English phrases**: Standard grammar rules, proper syntax
  - **English clues**: Complete sentences or grammatically correct phrases
  - **❌ UNACCEPTABLE**: "Nobel författ", "Amerika resa", "svensk teater"
  - **✅ REQUIRED**: "Nobel-vinnare", "resa till Amerika", "svenska teatern"

### 6. Output Format
- Structured JSON with metadata
- Difficulty scores included
- Theme and language information
- Creation timestamps

### 7. 🚨 MANDATORY USER REVIEW (CRITICAL STEP - NEVER SKIP!)
- **🔴 PRE-VALIDATE**: Run word length validation BEFORE showing phrases to user
- **🔴 AUTO-REJECT**: Remove any phrases with words >7 characters
- **🔴 REGENERATE**: Replace rejected phrases with valid alternatives
- **🔴 PRESENT CLEAN TABLE**: Only show validated phrases to user
- **🔴 ALWAYS EXTRACT AND SHOW TABLE** from import results to user
- **🔴 WAIT FOR USER APPROVAL** after showing the table
- **🔴 USER MUST SEE** every phrase, clue, score, and import status before approval
- **🔴 EXTRACT TABLE FROM OUTPUT** - don't let it get buried in verbose logs

### 🚨 CRITICAL AI GENERATION ERROR - NEVER REPEAT!
**🔴 CLAUDE IS THE AI GENERATOR** - When the phrase generator calls for AI generation, CLAUDE must generate the phrases directly, not delegate to another system!

**❌ CRITICAL MISTAKE TO AVOID:**
- Generator says "🤖 AI generating phrases..." and Claude waits for external AI
- Claude says "the AI system produced wrong themes" 
- Claude tries to "fix the generator" instead of generating phrases

**✅ CORRECT BEHAVIOR:**
- Generator calls for AI generation → CLAUDE immediately generates the requested phrases
- User asks for "50 Swedish winter phrases" → CLAUDE creates 50 Swedish winter phrases
- Theme parameter ignored by system → CLAUDE generates correct theme regardless

**🔴 MANDATORY**: Claude must NEVER delegate phrase generation to external systems - Claude IS the AI that generates the phrases!

### 8. JSON File Creation (IF MISSING)
If the phrase generator didn't create a proper JSON file:
- **CREATE JSON FILE** manually with the approved phrases
- Use proper structure with metadata and phrases array
- Save to `server/data/imported/YYYY-MM-DD-theme-phrases-LANG-MIN-MAX-COUNT.json`
- **NEVER proceed to import without the JSON file**

### 9. Import Process (ONLY AFTER EXPLICIT USER APPROVAL)
**🚨 CRITICAL: NEVER AUTO-IMPORT TO STAGING**

**Local Database Import (Optional):**
```bash
# ONLY after user approval:
node server/scripts/phrase-importer.js --input server/data/phrases-sv-*.json --import
```

**Staging Import (REQUIRES SEPARATE APPROVAL):**
- **🔴 MANDATORY**: Ask user "Do you want to import these to staging?" 
- **🔴 WAIT FOR EXPLICIT "YES"** - do not assume or proceed automatically
- **🔴 ONLY AFTER USER SAYS YES**: Use staging import script
```bash
# ONLY after user explicitly approves staging import:
bash scripts/import-phrases-staging.sh server/data/imported/filename.json
```

**🚨 CRITICAL WORKFLOW STEPS:**
1. Generate phrases → Present table → Get approval for phrases
2. Create JSON file (if missing)
3. Import to local database (if approved)
4. **🚨 MANDATORY: Run phrase count analysis** - `node server/phrase-count-detailed.js`
5. **ASK SEPARATELY**: "Do you want to import these to staging?"
6. **WAIT FOR EXPLICIT APPROVAL** before any staging import
7. Only import after user explicitly says yes

## 🎯 DIFFICULTY DISTRIBUTION REQUIREMENTS

### Core Principle
For ANY requested range (e.g., 30-100), phrases MUST be distributed across the FULL range:

### Distribution Algorithm
1. **Divide range into equal buckets** (e.g., 30-100 = 7 buckets of ~10 points each)
2. **Select 1-2 phrases from EACH bucket** to ensure spread
3. **NEVER cluster >50% of phrases** in one narrow band

### Example: 30-100 range with 10 phrases
- **30-39**: 1-2 phrases
- **40-49**: 1-2 phrases  
- **50-59**: 1-2 phrases
- **60-69**: 1-2 phrases
- **70-79**: 1-2 phrases
- **80-89**: 1-2 phrases
- **90-100**: 0-1 phrases

### What NOT to Do
- ❌ **BAD**: 8 phrases in 40-49, 1 in 30-39, 1 in 50-59 (80% clustering)
- ✅ **GOOD**: Even distribution across the requested range

## 🎯 SELECTION ALGORITHM REQUIREMENTS

When selecting final phrases from 40 candidates, use intelligent distribution:

### 6-Step Selection Process
1. **Calculate target buckets** based on requested range
2. **Score each candidate phrase** for difficulty using difficulty-algorithm
3. **Sort candidates into difficulty buckets**
4. **Select 1-2 best phrases from each bucket** (quality + theme + variety)
5. **Ensure no bucket is empty** and no bucket has >30% of total phrases
6. **Prioritize**: grammar > theme alignment > difficulty spread > clue creativity

## Current Implementation

### 🤖 CLAUDE IS THE AI PHRASE GENERATOR
- **WHO GENERATES**: Claude (the AI assistant) generates all phrases dynamically
- **NO HARDCODED PHRASES**: All phrases must be freshly generated for each request
- **NEVER USE**: Hardcoded or pre-written phrase lists
- **ALWAYS GENERATE**: Fresh, theme-specific phrases for each user request

### 3-Step AI Process (CLAUDE PERFORMS THIS)
1. **🤖 CLAUDE GENERATES**: Create 30 fresh phrase candidates with theme and difficulty
2. **🤖 CLAUDE FIXES**: Apply Swedish grammar rules and corrections (see critical rules below)  
3. **🤖 CLAUDE SELECTS**: Choose best phrases with proper difficulty distribution

**🔴 CRITICAL**: When the phrase generation script calls AI functions, CLAUDE must respond with actual generated phrases in the correct JSON format

**🚨 CRITICAL THEME CONTENT REQUIREMENTS:**
- **NEVER use generic terms** - "roman", "dikt", "magi", "trolldom" are INVALID
- **ALWAYS use specific references** - actual author names, book titles, characters, spells
- **Literature**: "Astrid Lindgren", "Harry Potter", "Röda rummet", "Hamlet"  
- **Fantasy**: "Gandalf", "Hogwarts", "Sauron", "Excalibur", "unicorn"
- **All themes**: Must be recognizable, specific content from that domain

**🚨 CRITICAL GRAMMAR REQUIREMENTS:**
- **🔴 MANDATORY**: Perfect grammar in BOTH phrases AND clues
- **Swedish grammar rules**: Possessive forms, compound words, proper articles, correct word order
- **English grammar rules**: Proper syntax, complete phrases, correct tense usage
- **❌ REJECT immediately**: Any phrase or clue with grammar errors
- **🔴 NEVER SKIP**: Grammar validation must be applied to every single phrase/clue pair
- **Examples of MANDATORY corrections**:
  - "Strindberg drama" → "Strindbergs drama" (possessive)  
  - "Nobel författ" → "Nobel-vinnare" (compound + article)
  - "Amerika resa" → "resa till Amerika" (proper word order)

### 🚨 CRITICAL SWEDISH GRAMMAR RULES (MANDATORY APPLICATION)

#### Compound Words (Särskrivning Prevention)
**SÄRSKRIVNING** = incorrectly separating compound words with spaces

**RULE: Swedish compound words MUST be written as single words - NO SPACES allowed**

When two related words should form a compound, they must be joined without spaces. Swedish speakers naturally create compounds for related concepts (kitchen tools, food combinations, cooking processes). 

Examples: "ris skål" → "risskål", "grädde sås" → "gräddsås", "kock kniv" → "kockkniv"

#### Grammar Rules to ALWAYS Apply:
1. **No särskrivning**: Compound words = single words (no spaces)
2. **Double consonant reduction**: "soppa gryta" → "soppgryta" (remove duplicate consonant)
3. **Connecting consonants**: Add 's' when needed: "vitlök press" → "vitlökspress"
4. **Natural compounds**: Only create compounds that Swedish speakers would naturally use
5. **🔴 CRITICAL: Word length validation**: Each word MUST be ≤7 characters after compound formation

#### 🚨 MANDATORY Word Length Validation (≤7 characters)
**🔴 AUTOMATIC REJECTION**: Any word >7 characters MUST be rejected immediately

**Three-Stage Validation Process:**
1. **Generate** phrases using AI
2. **🔴 AUTO-VALIDATE**: Run automatic word length check on ALL phrases
3. **🔴 PRESENT**: Only show validated phrases to user

**Auto-Rejection Examples:**
- "kryddträdgård" (13 chars) → AUTO-REJECT → Replace with "örter" (5 chars)
- "vitlökspress" (12 chars) → AUTO-REJECT → Replace with "vitlök" (6 chars)
- "molekylkök" (10 chars) → AUTO-REJECT → Replace with "molekyl" (7 chars)
- "flambera" (8 chars) → AUTO-REJECT → Replace with "flambé" (6 chars)

**🔴 NEVER**: Present phrases with >7 character words to user
**🔴 ALWAYS**: Pre-validate and fix/replace before user review

#### Validation Checklist for EVERY Swedish Phrase AND Clue:
- [ ] **🔴 FIRST**: Each word ≤7 characters (AUTO-REJECT if not)
- [ ] **🔴 PHRASE GRAMMAR**: No spaces in compound words (särskrivning check)
- [ ] **🔴 PHRASE GRAMMAR**: Correct possessive forms ("Lindgrens" not "Lindgren")
- [ ] **🔴 PHRASE GRAMMAR**: Natural Swedish compound formation
- [ ] **🔴 CLUE GRAMMAR**: Proper word order (subject-verb-object where applicable)
- [ ] **🔴 CLUE GRAMMAR**: Correct articles (en/ett/den/det)
- [ ] **🔴 CLUE GRAMMAR**: Proper compound formation in clues
- [ ] **🔴 CLUE GRAMMAR**: Complete grammatical phrases, not fragments
- [ ] **🔴 BOTH**: Would a native Swedish speaker approve both phrase AND clue?

#### Word Length Pre-Validation Function
```javascript
function validateWordLength(phrases) {
  return phrases.filter(phrase => {
    const words = phrase.phrase.split(' ');
    const validLength = words.every(word => word.length <= 7);
    if (!validLength) {
      console.log(`❌ REJECTED: "${phrase.phrase}" - contains word(s) >7 characters`);
      return false;
    }
    return true;
  });
}
```

**🔴 IMPLEMENTATION REQUIREMENT**: This validation MUST run before presenting phrases to user

## 🚨 CRITICAL: User Approval Process (MANDATORY STEP)

### 🔴 NEVER IMPORT WITHOUT APPROVAL
- **🔴 ALWAYS PRESENT** generated phrases in a review table
- **🔴 WAIT FOR EXPLICIT USER APPROVAL** before running import commands
- **🔴 USER MUST APPROVE**: phrases, clues, difficulty scores, and theme relevance
- **🔴 USER WILL CHECK**: difficulty distribution quality (no bad clustering)
- **🔴 CLAUDE MUST STOP** and wait for user response before proceeding with import

### Review Table Format (MANDATORY TO SHOW USER)
**🔴 ALWAYS EXTRACT THIS TABLE FROM IMPORT OUTPUT AND PRESENT TO USER:**

| Phrase | Clue | Score | Language | Imported | Reason |
|--------|------|-------|----------|----------|---------|
| [phrase] | [clue] | [score] | [lang] | ✅/❌ | [reason] |

**🔴 CRITICAL**: Extract this table from verbose output and present clearly to user
**🔴 NEVER**: Let the table get buried in logs - always highlight it separately

## 🔒 SECURITY UPDATE: Admin API Endpoints Removed

### What Changed
- **All admin batch import endpoints removed** (security update)
- **Replaced with secure direct database script access**
- **Benefits**: No network exposure, better performance, reduced attack surface

### New Secure Import Method
```bash
# Direct database access only (no HTTP API)
node scripts/phrase-importer.js --input file.json --import
```

### Import Script Environment Detection
The `import-phrases.js` script automatically detects the environment:
- **Local**: Uses `localhost` for database connection
- **Docker**: Detects Docker environment and uses `postgres` service name
- **Configurable**: Can override with environment variables:
  - `DB_HOST` - Database host (auto-detected if not set)
  - `DB_PORT` - Database port (default: 5432)
  - `DB_NAME` - Database name (default: anagram_game)
  - `DB_USER` - Database user (default: postgres)
  - `DB_PASSWORD` - Database password (default: postgres)
  - `DOCKER_ENV=true` - Force Docker mode

### Security Benefits
- **No network exposure** for admin operations
- **Better performance** with direct database access
- **Reduced attack surface** - no HTTP endpoints to exploit
- **Cleaner architecture** - fewer services to secure
- **🚨 CRITICAL: Difficulty scores calculated server-side** - Import script NEVER accepts pre-calculated difficulty scores
- **Algorithm integrity** - Uses shared difficulty-algorithm.js to ensure consistent scoring

### 🚨 CRITICAL FIX: Import Script Security Update (August 2025)
**FIXED VULNERABILITY**: Import script was accepting external difficulty scores with dangerous fallback to difficulty=1

**Root Cause**: Line 50 had `const phraseDifficulty = phraseData.difficulty || 1;` which caused 158 phrases to get incorrect difficulty=1 scores.

**Security Fix**: 
- **✅ FIXED**: Import script now ALWAYS calculates difficulty server-side using `shared/difficulty-algorithm.js`
- **✅ REMOVED**: Dangerous external difficulty score acceptance  
- **✅ ELIMINATED**: Fallback to difficulty=1 that caused scoring failures
- **✅ ENFORCED**: Server-side calculation for ALL imports, ensuring security and consistency

**Impact**: All future imports now use proper difficulty calculation. No more scoring failures or security risks from external JSON files.

## Phrase Generation Scripts

### Main Generation Script
```bash
# From project root, cd to server directory first:
cd server && node scripts/phrase-generator.js --range difficulty-range --count count --language language --theme theme
```

### Parameters
- **difficulty-range**: e.g., "1-100", "30-70" 
- **count**: number of phrases to generate
- **language**: "sv" for Swedish, "en" for English
- **theme**: topic category (cooking, computing, nature, etc.)

### ⚠️ CRITICAL WORKFLOW REMINDER
```bash
# 1. Generate phrases (from project root)
cd server && node scripts/phrase-generator.js --range 1-100 --count 30 --language sv --theme cooking

# 2. 🚨 MANDATORY: Present phrases in table format to user for approval
# 3. 🚨 MANDATORY: Wait for explicit user approval 
# 4. ONLY AFTER APPROVAL: Import phrases
cd server && node scripts/phrase-importer.js --input data/phrases-sv-*.json --import

# 5. 🚨 MANDATORY: Run phrase count analysis after successful import
node server/phrase-count-detailed.js
```

### Import Script
```bash
cd server
node scripts/phrase-importer.js --input data/phrases-*.json --import
```

### Preview Mode
```bash
# Generate without importing (safe preview)
node scripts/phrase-importer.js --input data/phrases-*.json --dry-run
```

## Quality Assurance

### Grammar Validation
- **🚨 CRITICAL**: Perfect grammar validation for BOTH phrases AND clues
- **🚨 CRITICAL**: Word length validation FIRST (≤7 characters per word)
- **🚨 CRITICAL**: Swedish compound words must be single words (no särskrivning!)
- **🚨 CRITICAL**: Swedish possessive forms must be correct ("Lindgrens" not "Lindgren")
- **🚨 CRITICAL**: Swedish word order must be proper ("resa till Amerika" not "Amerika resa")
- **🚨 CRITICAL**: Swedish articles and compounds ("Nobel-vinnare" not "Nobel författ")
- **MANDATORY**: Pre-validate BOTH phrase and clue grammar before user review
- **MANDATORY**: Apply särskrivning prevention rules to ALL Swedish content
- **MANDATORY**: Reject any phrase/clue pair with grammar errors
- Language-specific patterns applied to both phrases and clues
- 3-step validation: word length → grammar → theme relevance

### Theme Relevance
- **🚨 CRITICAL: Use SPECIFIC theme content, NOT generic terms**
- **Literature theme**: Author names, book titles, character names, literary movements
  - ✅ CORRECT: "Astrid Lindgren", "Pippi Långstrump", "Selma Lagerlöf"  
  - ❌ WRONG: "roman", "bok", "författare" (too generic)
- **Fantasy theme**: Specific creatures, spells, magical items, fantasy authors/works
  - ✅ CORRECT: "Gandalf", "Sauron", "Middle Earth", "Tolkien"
  - ❌ WRONG: "magi", "trolldom", "fantasy" (too generic)
- **All themes**: Must reference actual, recognizable content from that domain
- Thematic consistency checked
- Contextual appropriateness verified

### Difficulty Accuracy
- Scoring algorithm applied consistently
- Distribution requirements enforced
- Range compliance verified

### Technical Validation
- Word length limits enforced
- Character restrictions applied
- JSON format validation

## Troubleshooting

### Common Issues

#### Wrong Working Directory
```bash
# Error: Command not found
# Solution: Check you're in the right directory
pwd  # Should show correct path
cd /Users/fredriksafsten/Workprojects/anagram-game  # For generation
cd /Users/fredriksafsten/Workprojects/anagram-game/server  # For import
```

#### Import Fails
```bash
# Error: File not found
# Solution: Check file path and permissions
ls -la server/data/phrases-*.json  # Verify files exist
```

#### Bad Difficulty Distribution
```bash
# Error: Clustering detected
# Solution: Regenerate with better distribution algorithm
# Check: No more than 50% in any single difficulty band
```

#### Staging Server Access
```bash
# Error: SSH connection failed
# Solution: Verify Pi server is accessible
ssh pi@192.168.1.222 "echo 'Connection OK'"
```

#### Staging Import "Failed to copy to container"
```bash
# Error: Failed to copy to container
# Cause: Missing /app/data directory in Docker container
# Solution: Create the directory and fix permissions
ssh pi@192.168.1.222 "docker exec anagram-game-server mkdir -p /app/data"
ssh pi@192.168.1.222 "docker exec -u root anagram-game-server chown nodejs:nodejs /app/data"

# Then retry import:
bash Scripts/import-phrases-staging.sh server/data/imported/*.json
```

#### Multiple File Import Strategy
```bash
# Strategy 1: Import all files at once (recommended)
bash Scripts/import-phrases-staging.sh server/data/imported/*.json

# Strategy 2: Import files one by one (if bulk fails)
bash Scripts/import-phrases-staging.sh server/data/imported/file1.json
bash Scripts/import-phrases-staging.sh server/data/imported/file2.json

# The script automatically:
# - Creates Docker /app/data directory if missing
# - Handles duplicates (skips existing phrases)
# - Moves imported files to imported-on-stage/
# - Provides detailed import statistics
```

## Best Practices

### Before Generation
1. ✅ Verify working directory
2. ✅ Check theme validity
3. ✅ Confirm difficulty range
4. ✅ Ensure adequate count for distribution

### During Generation
1. ✅ Monitor AI processing steps
2. ✅ Verify grammar corrections applied
3. ✅ Check difficulty distribution
4. ✅ Validate theme alignment

### Before Import
1. ✅ Present review table to user
2. ✅ Get explicit approval
3. ✅ Verify file format and content
4. ✅ Check database connectivity

### After Import
1. ✅ Verify phrases in database
2. ✅ Test phrase retrieval
3. ✅ Confirm difficulty scoring
4. ✅ Validate in-game functionality
5. ✅ **🚨 MANDATORY: Run phrase count analysis** - `node server/phrase-count-detailed.js`

## Database Analysis Tools

### Phrase Count Analysis Script
The `phrase-count-detailed.js` script provides comprehensive phrase database analysis with support for both local and staging environments.

#### Usage
```bash
# Local database analysis
node server/phrase-count-detailed.js

# Staging database analysis  
node server/phrase-count-detailed.js staging

# Staging with custom IP
node server/phrase-count-detailed.js staging 10.0.0.5

# Show help
node server/phrase-count-detailed.js --help
```

#### Output Format
The script provides three analytical views:

**1. Cross-tabulation Table (Primary View)**
```
┌─────────┬─────────────┬─────────┬─────────┬────────────────┬────────────────┬────────────────┐
│ (index) │ theme       │ english │ swedish │ avg_difficulty │ min_difficulty │ max_difficulty │
├─────────┼─────────────┼─────────┼─────────┼────────────────┼────────────────┼────────────────┤
│ 0       │ 'null'      │ '248'   │ '199'   │ '53.6'         │ 31             │ 250            │
│ 1       │ 'cooking'   │ '30'    │ '30'    │ '59.8'         │ 15             │ 98             │
│ 2       │ 'golf'      │ '0'     │ '30'    │ '100.0'        │ 52             │ 148            │
└─────────┴─────────────┴─────────┴─────────┴────────────────┴────────────────┴────────────────┘
```

**2. Difficulty Distribution**
```
┌─────────┬─────────────────────┬───────┬───────────┐
│ (index) │ difficulty_range    │ count │ avg_score │
├─────────┼─────────────────────┼───────┼───────────┤
│ 0       │ '40-59 (Medium)'    │ '363' │ '48.8'    │
│ 1       │ '60-79 (Hard)'      │ '82'  │ '66.9'    │
│ 2       │ '20-39 (Easy)'      │ '67'  │ '35.1'    │
└─────────┴─────────────────────┴───────┴───────────┘
```

**3. Summary by Theme**
- Lists all themes with phrase counts
- Sorted by popularity (descending)

**4. Summary by Language**  
- Language distribution statistics
- Total phrase count

**5. Overall Difficulty Statistics**
- Average, min, max difficulty levels
- Standard deviation and phrase distribution

#### Database Configuration
- **Local**: Uses existing `./database/connection.js`
- **Staging**: Creates direct PostgreSQL connection
  - Default host: `192.168.1.222` (Pi staging)
  - Database: `anagram_game`
  - User/Password: `postgres/postgres`
  - Port: `5432`

#### Use Cases
- **Content Planning**: Identify theme gaps and language imbalances
- **Quality Assurance**: Monitor phrase distribution after imports
- **Deployment Verification**: Compare local vs staging phrase counts
- **Analytics**: Track content growth over time

#### Connection Management
- Automatic connection pooling for staging
- Proper connection cleanup on exit/error
- Error handling with graceful degradation

#### Examples
```bash
# Check local development database
node server/phrase-count-detailed.js

# Verify staging deployment results  
node server/phrase-count-detailed.js staging

# Connect to custom staging environment
node server/phrase-count-detailed.js staging 192.168.1.100
```

#### Environment Comparison (August 2025)

**Local Development Database (Updated August 2025):**
- **Total Phrases**: 140 (after cleanup and optimization)
- **Languages**: English (70), Swedish (70) - perfect balance
- **Themes**: 3 active themes - all content properly categorized
- **Difficulty**: Average 72.5, range 15-148, well-distributed across difficulty bands
- **Theme Distribution**: Golf (60), Cooking (60), Computing (20)
- **Language Balance**: Golf theme now has both English and Swedish versions

**Pi Staging Database:**
- **Total Phrases**: 15 (minimal test set)
- **Languages**: English only (15 phrases)
- **Themes**: All unthemed
- **Difficulty**: Average 1.9, range 1-3, all very easy phrases
- **Status**: Basic test data for deployment verification

**Key Insights:**
- Staging environment needs content deployment from local development
- Local database has been optimized with perfect language balance (70 English, 70 Swedish)
- All themes now have proper categorization (no unthemed content)
- Golf theme has been balanced with both English and Swedish versions
- Database cleanup removed 454 unthemed/test phrases, improving overall quality
- Difficulty distribution is well-balanced across all ranges (15-148)

## Integration with Game System

### Difficulty Algorithm Integration
- Phrases scored using `shared/difficulty-algorithm-config.json`
- Single source of truth for both iOS and server
- Client-side scoring eliminates network calls during typing

### Database Integration
- Direct PostgreSQL operations
- Secure script-based import
- No HTTP API exposure
- Transaction-based operations

### Real-time Integration
- Generated phrases available immediately after import
- WebSocket notifications for new content
- Dynamic difficulty matching
- Theme-based phrase selection