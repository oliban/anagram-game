# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Claude Interactions
- **Testing Workflow**: After implementing features/fixes, you build and deploy to two test simulators (iPhone 15 and iPhone 15 Pro) using the build scripts, then await my feedback from testing before proceeding.

## Project Overview
iOS "Anagram Game" for iPhone and Apple Watch built with SwiftUI. Players drag letter tiles to form words from scrambled sentences.

## Development Workflow
- **Progress Tracking**: Update `DEVELOPMENT_PROGRESS.md` checkboxes as steps complete
- **Current Focus**: Following 8-step implementation plan from project setup through Apple Watch version
- **Time Estimates**: Each step has rough time estimates (30-120 minutes) for session planning
- **Server Log Monitoring**: YOU are responsible for monitoring server logs automatically during testing. Do NOT wait for me to paste logs. Use proper log capture techniques (background processes, log files, tail commands) to monitor real-time server output and connection behavior.
- **Testing Process**: After implementing features/fixes, run `./build_multi_sim.sh` to build and deploy to both iPhone 15 and iPhone 15 Pro simulators, then automatically monitor server logs and iOS device logs for debugging

## Current Implementation Status
Track progress in `DEVELOPMENT_PROGRESS.md` - update checkboxes as each step completes.

# Development Partnership

We're building production-quality iOS code together. Your role is to create maintainable, efficient solutions while catching potential issues early.

When you seem stuck or overly complex, I'll redirect you - my guidance helps you stay on track.

## 🚨 CODE QUALITY IS MANDATORY
**ALL code must follow Swift/iOS best practices!**  
Clean, maintainable code. Zero tolerance for bad patterns.  
These are not suggestions. Fix ALL issues before continuing.

## CRITICAL WORKFLOW - ALWAYS FOLLOW THIS!

### Research → Plan → Implement
**NEVER JUMP STRAIGHT TO CODING!** Always follow this sequence:
1. **Research**: Explore the codebase, understand existing patterns
2. **Plan**: Create a detailed implementation plan and verify it with me  
3. **Implement**: Execute the plan with validation checkpoints

When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."

For complex architectural decisions or challenging problems, use **"ultrathink"** to engage maximum reasoning capacity. Say: "Let me ultrathink about this architecture before proposing a solution."

### USE MULTIPLE AGENTS!
*Leverage subagents aggressively* for better results:

* Spawn agents to explore different parts of the codebase in parallel
* Use one agent to write tests while another implements features
* Delegate research tasks: "I'll have an agent investigate the game model while I analyze the UI structure"
* For complex refactors: One agent identifies changes, another implements them

Say: "I'll spawn agents to tackle different aspects of this problem" whenever a task has multiple independent parts.

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component  
- When something feels wrong
- Before declaring "done"
- **WHEN CODE PATTERNS FEEL WRONG** ❌

> Why: You can lose track of what's actually working. These checkpoints prevent cascading failures.

### 🚨 CRITICAL: Code Quality Is Required
**When code doesn't follow best practices:**
1. **STOP AND REFACTOR** - Don't continue with bad patterns
2. **FIX THE APPROACH** - Use proper Swift/iOS patterns
3. **VERIFY CLEANLINESS** - Ensure code follows standards
4. **CONTINUE ORIGINAL TASK** - Return to what you were doing
5. **NEVER IGNORE** - There are no shortcuts, only quality

This includes:
- Proper memory management patterns
- SwiftUI best practices
- Clean architecture principles
- Readable, maintainable code
- Proper error handling

Your code must be production-quality. No exceptions.

**Recovery Protocol:**
- When interrupted by code quality issues, maintain awareness of your original task
- After fixing patterns and ensuring quality, continue where you left off
- Use the todo list to track both the fix and your original task

## Working Memory Management

### When context gets long:
- Re-read this CLAUDE.md file
- Summarize progress in a PROGRESS.md file
- Document current state before major changes

### Maintain TODO.md:
```
## Current Task
- [ ] What we're doing RIGHT NOW

## Completed  
- [x] What's actually done and tested

## Next Steps
- [ ] What comes next
```

## Swift/iOS-Specific Rules

### FORBIDDEN - NEVER DO THESE:
- **NO force unwrapping (!)** without explicit safety checks
- **NO retain cycles** - use `weak` and `unowned` properly
- **NO blocking the main thread** - use async/await for heavy operations
- **NO** keeping old and new code together
- **NO** migration functions or compatibility layers
- **NO** versioned function names (processV2, handleNew)
- **NO** complex inheritance hierarchies - prefer composition
- **NO** TODOs in final code

### Required Standards:
- **Delete** old code when replacing it
- **Meaningful names**: `userIdentifier` not `id`
- **Guard statements** for early returns and unwrapping
- **Proper memory management**: Use `weak self` in closures
- **SwiftUI best practices**: Use `@State`, `@Binding`, `@ObservableObject` correctly
- **Error handling**: Use `Result<Success, Failure>` and proper error propagation
- **Unit tests** with XCTest for complex logic
- **Main thread for UI**: Use `@MainActor` or `DispatchQueue.main.async`

## Implementation Standards

### Our code is complete when:
- ✅ Follows Swift/iOS best practices
- ✅ Uses proper memory management patterns
- ✅ Implements clean, readable logic
- ✅ Old code is deleted
- ✅ Swift documentation on public interfaces
- ✅ Handles errors gracefully

### Testing Strategy
- Complex game logic → Write XCTest unit tests first
- Simple UI components → Write tests after
- Performance-critical paths → Add XCTest performance tests
- Skip tests for simple view modifiers and basic SwiftUI

### Project Structure
```
Models/             # Data models and game logic
Views/              # SwiftUI views and UI components
Resources/          # Assets, data files, localizations
Watch/              # Apple Watch specific code
Anagram GameTests/  # Unit tests
```

## Problem-Solving Together

When you're stuck or confused:
1. **Stop** - Don't spiral into complex solutions
2. **Delegate** - Consider spawning agents for parallel investigation
3. **Ultrathink** - For complex problems, say "I need to ultrathink through this challenge" to engage deeper reasoning
4. **Step back** - Re-read the requirements
5. **Simplify** - The simple solution is usually correct
6. **Ask** - "I see two approaches: [A] vs [B]. Which do you prefer?"

My insights on better approaches are valued - please ask for them!

## Performance & Security

### **Measure First**:
- No premature optimization
- Use Instruments for real bottlenecks
- Profile with Time Profiler and Allocations

### **iOS Best Practices**:
- Validate all user inputs
- Use Keychain for sensitive data storage
- Proper data protection and privacy
- Follow Apple's Human Interface Guidelines

## Communication Protocol

### Progress Updates:
```
✓ Implemented tile physics (all tests passing)
✓ Added word detection logic  
✗ Found issue with memory retention - investigating
```

### Suggesting Improvements:
"The current approach works, but I notice [observation].
Would you like me to [specific improvement]?"

## Working Together

- This is always a feature branch - no backwards compatibility needed
- When in doubt, we choose clarity over cleverness
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

Avoid complex abstractions or "clever" code. The simple, obvious solution is probably better, and my guidance helps you stay focused on what matters.

## Code Review and Testing
- Always have me test the code changes before committing anything to git
- **Multi-Simulator Testing**: Use the provided build scripts to test multiplayer functionality:
  - `./build_multi_sim.sh` - Full build and deploy to both iPhone 15 and iPhone 15 Pro simulators
  - `./quick_test.sh` - Quick relaunch if app already installed
  - `./setup_sims.sh` - Boot simulators only
- After deployment, automatically monitor server logs and iOS device logs to analyze connection patterns and debug issues before proceeding with next tasks

## CRITICAL: Proven Multi-Simulator Deployment Flow
**When deploying new app versions, ALWAYS follow this exact sequence:**

### Phase 1: Server Setup and Versioning
1. **Kill existing server**: `pkill -f "node server.js"`
2. **Start fresh server**: `node server/server.js > server/server_output.log 2>&1 &`
3. **Monitor logs**: `tail -f server/server_output.log &`
4. **Increment version**: Update both `CFBundleVersion` and `CFBundleShortVersionString` in Info.plist

### Phase 2: Build Process
1. **Clean build**: `xcodebuild clean -project "Anagram Game.xcodeproj" -scheme "Anagram Game"`
2. **Build with timeout**: Use 5-minute timeout and local derived data:
   ```
   xcodebuild -project "Anagram Game.xcodeproj" -scheme "Anagram Game" \
   -destination "id=AF307F12-A657-4D6A-8123-240CBBEC5B31" \
   -derivedDataPath ./build build
   ```

### Phase 3: Deployment to Both Simulators
1. **Install on iPhone 15**: `xcrun simctl install AF307F12-A657-4D6A-8123-240CBBEC5B31 "./build/Build/Products/Debug-iphonesimulator/Anagram Game.app"`
2. **Install on iPhone 15 Pro**: `xcrun simctl install 86355D8A-560E-465D-8FDC-3D037BCA482B "./build/Build/Products/Debug-iphonesimulator/Anagram Game.app"`
3. **Launch iPhone 15**: `xcrun simctl launch AF307F12-A657-4D6A-8123-240CBBEC5B31 com.fredrik.anagramgame`
4. **Launch iPhone 15 Pro**: `xcrun simctl launch 86355D8A-560E-465D-8FDC-3D037BCA482B com.fredrik.anagramgame`

### Phase 4: Verification
- **Monitor server logs** for player connections and WebSocket activity
- **Verify both devices** show successful registration and connection
- **Check API calls** are flowing (status, players/online, phrases/for endpoints)

## Post-Deployment Workflow
- **Always do this after deploying a fix**:
  - Verify full functionality across both test simulators
  - Run comprehensive tests to ensure no regressions
  - Await detailed user feedback before marking task complete