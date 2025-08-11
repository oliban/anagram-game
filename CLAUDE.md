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

## 📚 QUICK REFERENCE GUIDES
- 🐛 **Debugging & Logging**: `docs/DEBUGGING_GUIDE.md`
- 🚀 **Deployment & Build**: `docs/DEPLOYMENT_GUIDE.md`
- 🛡️ **Security & Testing**: `docs/SECURITY_GUIDE.md`
- 🧪 **Test Infrastructure**: `docs/TESTING_GUIDE.md`
- 📝 **Phrase Generation**: `docs/PHRASE_GENERATION_GUIDE.md`
- 📚 **Commands & API**: `docs/REFERENCE_COMMANDS.md`
- 🏗️ **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`

## WORKING MEMORY MANAGEMENT
- **When context gets long**: Re-read this CLAUDE.md file, summarize progress in PROGRESS.md, document current state before major changes
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

---

## ESSENTIAL BUILD WARNINGS
- **Never build the apps with clean flag if there is not a very good reason for it!**
- **🚨 CRITICAL: If you use --clean flag, you MUST immediately re-associate logged-in players afterward!**
  - Clean builds reset device IDs, breaking auto-login for existing players
  - After clean build, run device association commands from `docs/device-user-association-guide.md`