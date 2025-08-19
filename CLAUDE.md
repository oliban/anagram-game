# Wordshelf - iOS Development Guide

## Project Overview
iOS multiplayer word game built with SwiftUI + SpriteKit. Players drag letter tiles to form words from scrambled sentences.

## 🚨 CORE WORKFLOW - ALWAYS FOLLOW

### 🚨 CRITICAL: GIT-FIRST DEVELOPMENT (MANDATORY)
**❌ NEVER CREATE CUSTOM IMPLEMENTATIONS** - Always use git as the source of truth for all functionality.

**🔴 FUNDAMENTAL RULE: FETCH FROM GIT BEFORE ANY WORK**
```bash
# MANDATORY: Start every session with this command
git pull origin main
```

**🚨 IMPLEMENTATION RECOVERY PROTOCOL:**
When any functionality is missing, broken, or incomplete:
1. **NEVER write custom implementations**
2. **ALWAYS search git history first**: `git log --grep="missing_feature" --oneline`
3. **Extract from git**: `git show COMMIT:path/to/file.js > temp_file.js`
4. **Replace with git version**: Copy the exact git implementation
5. **Deploy git version**: Test the original implementation before making any changes

**🔥 EXAMPLES OF CRITICAL MISTAKES TO AVOID:**
- ❌ Writing new endpoint implementations when they exist in git
- ❌ Recreating database functions instead of applying git versions
- ❌ Custom scoring logic when git has the working version
- ❌ Any "quick fix" that bypasses git history

### 🌊 GITFLOW WORKFLOW (MANDATORY)
**❌ NEVER COMMIT DIRECTLY TO MAIN** - Use proper GitFlow with automated testing and quality gates.

**Branch Structure:**
```
feature/* branches ──→ develop ──→ main ──→ production
    (daily work)      (integration)  (releases)  (deployment)
```

**Daily Development Process:**
1. **🚨 MANDATORY: Start with Git**: `git checkout develop && git pull origin develop`
2. **Start Feature**: `git checkout -b feature/my-feature`
3. **Research First**: Start with `code_map.swift` - check freshness (`head -n 1`), search with `grep -n`, then read specific sections **IMPORTANT** If the file is older than 1 hour - run `python3 code_map_generator.py . --output code_map.swift` from project root.
4. **Plan**: Create detailed implementation plan, verify with me before coding
5. **Implement**: Write production-quality Swift code following all best practices
6. **Push Feature**: `git push origin feature/my-feature` (triggers 5min quick tests)
7. **Test**: Deploy with `build_multi_sim.sh` (includes server health checks), await my feedback
8. **Create PR**: `gh pr create --base develop --title "feat: my feature"` (triggers 15min comprehensive tests)
9. **Release**: When ready, create `develop → main` PR (triggers 25min production tests + staging deployment)

**Quality Gates:**
- **Feature Branches**: ⚡ Quick API tests (5 min) - Safe to iterate
- **Develop Integration**: 🧪 Comprehensive tests (15 min) - Must pass to merge
- **Main Releases**: 🔒 Production tests + staging + manual approval (25+ min)

**Setup Command**: `./scripts/setup-gitflow.sh` (run once to initialize)

**When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."**

### 🚨 CRITICAL: CLAUDE IS THE AI PHRASE GENERATOR
**🔴 NEVER DELEGATE PHRASE GENERATION** - When users request phrases or the system calls for AI generation, CLAUDE must generate the phrases directly!

**❌ CRITICAL MISTAKES:**
- Waiting for "AI system" to generate phrases when Claude IS the AI
- Saying "the AI produced wrong themes" instead of generating correct themes
- Trying to "fix the generator" instead of generating requested phrases

**✅ CORRECT BEHAVIOR:**
- User requests phrases → Claude immediately generates them
- System shows "🤖 AI generating..." → Claude provides the generation
- Wrong theme/difficulty produced → Claude generates correct ones

### 🔍 MANDATORY PHRASE VALIDATION RULES
**🚨 CLAUDE MUST VERIFY EVERY PHRASE BEFORE PROVIDING:**

**📏 WORD LENGTH LIMITS:**
- ❌ **Each word max 7 characters** - "December" (8 chars) = INVALID
- ❌ **Total 1-4 words only** - 5+ words = INVALID

**🚫 CLUE RESTRICTIONS:**  
- ❌ **Clue cannot contain ANY word from the phrase** - "test" phrase with "this is a test" clue = INVALID
- ❌ **No exact phrase words in clue** - "quick fox" with "the quick animal" = INVALID

**🌐 LANGUAGE CONSISTENCY:**
- ✅ **Pure Swedish OK** - "vit snö" with "kall vinter" = VALID  
- ✅ **Pure English OK** - "white snow" with "cold winter" = VALID
- ❌ **Mixed languages** - Only if culturally appropriate (brand names, etc.)

**📋 VALIDATION CHECKLIST - RUN EVERY TIME:**
1. Count characters in each word (≤7 each)
2. Count total words (1-4 total)
3. Check clue doesn't contain phrase words
4. Verify language consistency
5. Confirm theme matches request


## CODE QUALITY REQUIREMENTS
- **Zero tolerance for bad patterns** - Stop and refactor immediately
- **No force unwrapping (!)** without safety checks
- **Proper memory management** - Use `weak self` in closures
- **SwiftUI best practices** - Correct `@State`, `@Binding`, `@ObservableObject` usage
- **Delete old code** when replacing - no migration functions or versioned names
- **NO FALLBACKS** - Never keep old code as fallback when rewriting functions
- **Meaningful names** - `userIdentifier` not `id`
- **Guard statements** for early returns and unwrapping

**Recovery Protocol**: When interrupted by code quality issues, maintain awareness of your original task. After fixing patterns and ensuring quality, continue where you left off. Use todo list to track both the fix and your original task.

**🚨 MISSING FUNCTIONALITY RECOVERY PROTOCOL:**
When encountering "missing" endpoints, functions, or features:
1. **STOP** - Do not write custom implementations
2. **Search git history**: `git log --grep="endpoint\|function_name" --oneline -20`
3. **Find working commit**: Look for commits that mention the missing functionality
4. **Extract original**: `git show COMMIT:path/to/file > /tmp/original.js`
5. **Replace current**: Copy the git version exactly, no modifications
6. **Test git version**: Verify the original implementation works
7. **Only then modify**: If changes are needed, start with the working git version

**Example Commands:**
```bash
# Find when an endpoint was added
git log --grep="scores/player" --oneline
git log --grep="statistics" --oneline

# Extract the original implementation
git show 77f1e0c:server/server.js | sed -n '/api\/scores\/player/,/^});$/p' > /tmp/endpoint.js

# Replace with git version
cp /tmp/endpoint.js services/game-server/routes/leaderboards.js
```

**Code is complete when**:
- ✅ Follows Swift/iOS best practices
- ✅ Uses proper memory management patterns
- ✅ Implements clean, readable logic
- ✅ Old code is deleted
- ✅ Swift documentation on public interfaces
- ✅ Handles errors gracefully
- ✅ **Includes appropriate DebugLogger.shared logging statements**

## SWIFT-SPECIFIC GUIDELINES
- **Async/await over callbacks**: `func fetchUser() async throws -> User`
- **@Observable over ObservableObject**: Use Swift 5.9+ observation framework
- **Capture lists required**: `{ [weak self] in self?.method() }` prevents retain cycles
- **Task lifecycle**: Use `.task { await loadData() }` for auto-cancellation
- **View composition**: Extract complex views into smaller components
- **State ownership**: Keep @State private, pass down as @Binding
- **Environment over singletons**: Use @Environment for shared state

## EFFICIENT RESEARCH PROTOCOL
**Code Map First**: Always start with `code_map.swift` for all research
- Check freshness: `head -n 1 code_map.swift` (regenerate if > 1 hour old)
- Search targets: `grep -n "ClassName\|propertyName" code_map.swift`
- Use line numbers to read specific sections
- Only use Task agents for complex multi-file relationships

**Forbidden**: Broad searches (`grep -r`, `find`), reading entire files, multiple agents for simple lookups

## PROBLEM-SOLVING STRATEGIES
- **Use multiple agents** for parallel investigation of different codebase parts
- **Ultrathink** for complex architectural decisions
- **Reality checkpoints** after each feature, before major changes, when patterns feel wrong
- **Ask for guidance** when stuck: "I see approaches [A] vs [B]. Which do you prefer?"

## KEY PRINCIPLES
- **NO LEGACY** - Always remove old code when building replacements
- **Clarity over cleverness** - Simple, obvious solutions preferred
- **Production quality only** - No shortcuts, no TODOs in final code
- **Feature branch** - No backwards compatibility needed
- **Measure first** - No premature optimization, use Instruments for real bottlenecks
- **Security minded** - Validate inputs, use Keychain for sensitive data

### 🚨 CRITICAL: COMPREHENSIVE TESTING PROTOCOL (MANDATORY)
**❌ NEVER CLAIM SOMETHING WORKS WITHOUT TESTING EVERY STEP**

**🔴 FUNDAMENTAL RULE: TEST BEFORE CLAIMING SUCCESS**
- **NEVER** say "this should work" or "everything is working" without actual verification
- **ALWAYS** test each component in the flow before moving to the next
- **MANDATORY** end-to-end testing before declaring completion

**📋 TESTING REQUIREMENTS:**
1. **Component Testing**: Test each individual piece (API endpoints, database queries, UI components)
2. **Integration Testing**: Test how components work together
3. **End-to-End Testing**: Test the complete user flow from start to finish
4. **Error Scenario Testing**: Test failure cases and error handling
5. **Cross-Environment Testing**: Test in the actual environment (local/staging/production)

**🧪 TESTING WORKFLOW:**
```bash
# Test each step before claiming it works
1. Test API endpoint: curl -X POST ... | jq '.'
2. Test database changes: psql -c "SELECT ..." 
3. Test UI component: Load page and verify functionality
4. Test complete flow: Simulate actual user interaction
5. Test error cases: Try invalid inputs, network failures
```

**✅ EVIDENCE REQUIRED BEFORE COMPLETION:**
- **HTTP Response Codes**: Show actual 200/201 success responses  
- **Database Records**: Verify data was actually created/updated
- **UI Functionality**: Confirm forms submit, pages load, buttons work
- **Error Handling**: Demonstrate graceful failure modes
- **Performance**: Verify acceptable response times

**❌ FORBIDDEN CLAIMS:**
- "The system is now working" (without showing test results)
- "This should fix it" (test it!)  
- "The API accepts requests" (show the actual successful response)
- "Everything is configured correctly" (prove it with tests)

**Recovery Protocol**: When you catch yourself making untested claims, immediately stop and run comprehensive tests for that component before continuing.

## 📚 QUICK REFERENCE GUIDES
- 🐛 **Debugging & Logging**: `docs/DEBUGGING_GUIDE.md`
- 🚀 **Deployment & Build**: `docs/DEPLOYMENT_GUIDE.md`
- 🛡️ **Security & Testing**: `docs/SECURITY_GUIDE.md`
- 🧪 **Test Infrastructure**: `docs/TESTING_GUIDE.md`
- 📝 **Phrase Generation**: `docs/PHRASE_GENERATION_GUIDE.md`
- 📚 **Commands & API**: `docs/REFERENCE_COMMANDS.md`
- 🏗️ **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`
- 🗄️ **Database Recovery**: `docs/DATABASE_RECOVERY_PROCEDURES.md`
- 📊 **Incident Report**: `docs/DATABASE_INCIDENT_REPORT.md`
- 🌐 **CLOUDFLARE TUNNEL FIX**: `docs/CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md` ⚠️ RECURRING ISSUE

## 🚀 DEPLOYMENT COMMANDS

### 🔴 CRITICAL: DOCKER CONTAINER DEPLOYMENT RULES
**❌ NEVER ASSUME FILES COPIED TO PI ARE IN THE CONTAINER**
- Copying files to `/home/pi/anagram-game/` does NOT update the running Docker container
- **ALWAYS** rebuild container OR copy directly into container
- **VERIFY** deployment with: `docker exec anagram-server cat /project/server/[file]`

**✅ CORRECT DEPLOYMENT SEQUENCE:**
```bash
# 1. Copy files to Pi
scp server/file.js pi@192.168.1.222:/home/pi/anagram-game/server/

# 2. EITHER rebuild container (slow but complete):
ssh pi@192.168.1.222 "cd /home/pi/anagram-game && docker-compose build server && docker-compose up -d"

# 3. OR copy directly to running container (fast for hotfixes):
ssh pi@192.168.1.222 "docker cp /home/pi/anagram-game/server/file.js anagram-server:/project/server/ && docker restart anagram-server"

# 4. ALWAYS verify the fix is deployed:
ssh pi@192.168.1.222 "docker exec anagram-server grep 'your-fix' /project/server/file.js"
```

### 🌐 CLOUDFLARE TUNNEL URL FIX (RECURRING ISSUE)
**🚨 THIS ISSUE KEEPS COMING BACK - READ CAREFULLY:**

**Problem**: Contribution links show `127.0.0.1:3000` or `localhost` instead of Cloudflare URL

**Root Cause**: Cloudflare tunnel forwards requests with these headers:
- `host: '127.0.0.1:3000'` (what Docker sees locally)
- `x-forwarded-host: 'bras-voluntary-survivor-presidential.trycloudflare.com'` (the REAL URL)

**✅ PERMANENT FIX - Always use this pattern:**
```javascript
// CORRECT: Check x-forwarded-host FIRST
const host = req.headers['x-forwarded-host'] || req.headers.host;

// WRONG: Using host directly
const host = req.headers.host; // This will be 127.0.0.1 on staging!
```

**Staging Detection Pattern:**
```javascript
const isStaging = 
  process.env.NODE_ENV === 'staging' ||
  (req?.headers?.['x-forwarded-host']?.includes('trycloudflare.com'));
```

### Standard Deployment Commands:
- **Deploy to Pi Staging**: `bash Scripts/deploy-to-pi.sh` (needs fixing - see below)
- **Check Deployment**: `bash Scripts/check-deployment.sh`
- **Build for Staging**: `./build_multi_sim.sh staging`
- **Import Phrases to Staging**: `bash Scripts/import-phrases-staging.sh <json-file>` (automated Docker import with safety checks)

## 🛡️ DATABASE SAFETY COMMANDS
- **Health Monitoring**: `bash Scripts/monitor-database-health.sh [ip]` (comprehensive system check)
- **Check Database Completeness**: `bash Scripts/check-database-completeness.sh [ip]` (verify all tables)
- **Create Database Backup**: `bash Scripts/backup-database.sh [ip]` (manual backup creation)
- **Restore Database Schema**: `bash Scripts/restore-database-schema.sh [ip]` (fix missing tables)
- **Setup Automated Backups**: `bash Scripts/setup-automated-backups.sh [ip]` (deploy backup system)

**🚨 CRITICAL DATABASE RULES:**
- **NEVER** make database changes without creating a backup first
- **ALWAYS** run completeness check before importing phrases  
- **ALWAYS** use import-phrases-staging.sh (includes all safety checks)
- **Monitor** backup system health weekly via automated scripts

## WORKING MEMORY MANAGEMENT
- **When context gets long**: Re-read this CLAUDE.md file, summarize progress in PROGRESS.md, document current state before major changes
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

---

## ESSENTIAL BUILD WARNINGS
- **Never build the apps with clean flag if there is not a very good reason for it!**
- **🚨 CRITICAL: If you use --clean flag, you MUST immediately re-associate logged-in players afterward!**
  - Clean builds reset device IDs, breaking auto-login for existing players
  - After clean build, run device association commands from `docs/device-user-association-guide.md`