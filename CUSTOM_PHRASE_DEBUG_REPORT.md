# Custom Phrase System Debug Report

## Overview
This document details the investigation and resolution of issues with the custom phrase system in the iOS Anagram Game multiplayer feature.

## Initial Problem
Custom phrases were being sent successfully from one player to another, but the receiving player never saw them in their next game. The phrases appeared to be consumed immediately without being used.

## Investigation Process

### Phase 1: Server-Side Verification
**Status: ✅ WORKING**
- Server logs confirmed phrases were being created successfully
- WebSocket notifications were being sent to correct players
- Phrases were being marked as consumed on the server
- Server-side implementation was functioning correctly

### Phase 2: iOS WebSocket Connection Issues
**Status: ⚠️ PARTIALLY WORKING**

#### Connection Problems Found:
1. **Xcode Dependency**: WebSocket connections only worked when app was launched through Xcode
2. **App Transport Security**: HTTP connections were blocked when running outside development environment
3. **Auto-Connect Failures**: Complex startup flow was hanging indefinitely

#### Solutions Applied:
1. **Added ATS Exception** in Info.plist to allow HTTP connections to local server
2. **Simplified Connection Flow**: Removed complex auto-connect, added manual "Test Connection" button
3. **Added Proper Timeouts**: Prevented infinite hanging on connection attempts

### Phase 3: UI Update Investigation
**Status: ❌ NOT WORKING → ✅ FIXED**

#### Problem Identified:
- WebSocket notifications were being received
- `lastReceivedPhrase` was being set (toast notifications worked)
- BUT `pendingPhrases` array was not updating in UI

#### Initial Theories Tested:
1. **SwiftUI Binding Issues**: Tried forcing array replacement instead of `.append()`
2. **Threading Issues**: Verified main thread updates
3. **Property Publishing**: Added manual `objectWillChange.send()`

#### Root Cause Discovery:
Used debug counters to track array modifications:
```
- WebSocket receives phrase → +1 to debugCounter
- GameModel immediately removes phrase → +100 to debugCounter
```

Pattern observed: 1 → 101 → 202 → 303
This revealed that **GameModel was immediately consuming phrases** as soon as they were added.

## Root Cause Analysis

### The Core Issue
The `GameModel.startNewGame()` method was being called too frequently, causing it to immediately check for and consume custom phrases whenever they arrived, before the UI could display them.

### Timeline of Events:
1. **Phrase arrives via WebSocket** → Added to `pendingPhrases` array
2. **GameModel triggered** (likely by state changes) → Calls `checkForCustomPhrases()`
3. **Phrase immediately consumed** → Removed from `pendingPhrases` within milliseconds
4. **UI never updates** → Array is empty before next render cycle

### Code Location:
The problematic code was in `GameModel.checkForCustomPhrases()`:
```swift
// Remove from local cache immediately
if let index = networkManager.pendingPhrases.firstIndex(where: { $0.id == firstPhrase.id }) {
    networkManager.pendingPhrases.remove(at: index)
    print("🎮 GAME: Removed phrase from local cache")
}
```

## Solution Implemented

### Temporary Fix (Proof of Concept):
Disabled the immediate phrase removal to verify the UI could display phrases:
```swift
// TEMPORARILY DISABLED: Remove from local cache immediately
// if let index = networkManager.pendingPhrases.firstIndex(where: { $0.id == firstPhrase.id }) {
//     networkManager.pendingPhrases.remove(at: index)
// }
```

**Result**: ✅ UI immediately started working - phrases appeared in "NEXT:" preview

### Proper Fix Required:
The complete solution needs to ensure `startNewGame()` is only called when:
1. **Game actually completes** (player solves puzzle)
2. **Manual game reset** (user action)
3. **App initialization** (one time only)

NOT when:
- Phrases arrive via WebSocket
- GameModel state changes
- UI updates occur

## Current Status

### ✅ Working Components:
1. **Server-side phrase system** - Complete and functional
2. **WebSocket communication** - Phrases sent and received correctly
3. **Toast notifications** - Players see when phrases arrive
4. **UI display** - Pending phrases and next phrase preview work
5. **Manual connection** - Test Connection button reliably establishes connection
6. **Phrase reception and display** - Custom phrases appear in "NEXT:" preview correctly

### ⚠️ Current Issue - Tiles Mismatch:
**CRITICAL BUG DISCOVERED**: The custom phrase appears correctly in the yellow "SOLUTION:" text, but the falling tiles correspond to a different phrase entirely.

**Symptoms**:
- Custom phrase shows in "SOLUTION:" (e.g., "test phrase")
- Falling tiles spell out a completely different phrase (e.g., "Be kind")
- This indicates the `currentSentence` and `scrambledLetters` are out of sync

**Root Cause Analysis**:
The issue appears to be multiple calls to `startNewGame()` causing race conditions:
1. **First call**: Sets `currentSentence` to custom phrase
2. **Second call**: Overwrites `currentSentence` with different phrase
3. **Tiles created**: Use letters from the second (wrong) phrase
4. **UI displays**: Shows the first (correct) phrase in solution text

**Attempted Fixes**:
1. Added `isStartingNewGame` flag to prevent concurrent calls - **UNSUCCESSFUL**
2. The timing issue persists, suggesting the calls are sequential, not concurrent

### ⚠️ Other Issues:
1. **Phrase consumption timing** - Currently disabled for testing
2. **Auto-connect on app launch** - Currently requires manual connection

### 🔧 Debugging Tools Added:
1. **Visual debug display** on game screen showing:
   - Socket connection status
   - Pending phrase count
   - Last received phrase
   - Debug counter for tracking array modifications
   - Current player information
   - Connection status details
2. **Manual test buttons** for connection and phrase testing
3. **Comprehensive logging** throughout the system
4. **Detailed call stack logging** for `startNewGame()` calls

## Lessons Learned

1. **Server logs vs iOS behavior**: Server logs showed success, but iOS had separate issues
2. **Development vs production networking**: App behavior differs significantly between Xcode launch and normal launch
3. **UI binding subtleties**: `@Published` arrays can be modified without UI updates if timing is wrong
4. **State management complexity**: Multiple systems (WebSocket, GameModel, UI) can interfere with each other
5. **Race conditions in async code**: Even with protection flags, sequential async calls can still cause state corruption
6. **Sentence/tiles synchronization**: UI can display one sentence while tiles represent another, indicating state management issues

## Critical Issue Details

### The Tiles Mismatch Problem
This is the most significant remaining issue. The flow appears to be:

1. **Phrase received** → Shows in "NEXT:" preview ✅
2. **Game completed** → Triggers new game start
3. **Custom phrase detected** → Sets `currentSentence` to custom phrase ✅
4. **Something overwrites sentence** → `currentSentence` changes to different phrase ❌
5. **Tiles created** → Uses wrong sentence for `scrambledLetters` ❌
6. **UI displays** → Shows original custom phrase but wrong tiles ❌

### Investigation Needed:
1. **Track sentence changes** - Add logging to `currentSentence` setter to see when/why it changes
2. **Identify multiple startNewGame calls** - Determine what's triggering the second call
3. **Fix timing/sequencing** - Ensure tiles are created from the same sentence shown in UI

## Next Steps (Priority Order)

1. **🔥 CRITICAL: Fix tiles mismatch** - Ensure tiles match the displayed solution
2. **Fix phrase consumption timing** - Restore proper consumption only on game completion
3. **Implement auto-connect** - Make connection automatic but reliable
4. **Test complete end-to-end flow** - Verify custom phrases work in actual gameplay
5. **Remove debug code** - Clean up temporary debugging additions
6. **Complete Step 3** - Mark custom phrase feature as finished

## Files Modified

### Core Implementation:
- `Models/NetworkManager.swift` - WebSocket handling and phrase management
- `Models/GameModel.swift` - Custom phrase integration and consumption
- `Views/PhraseCreationView.swift` - Phrase creation UI
- `Views/PhysicsGameView.swift` - UI display and debug information
- `Views/ContentView.swift` - Connection management

### Configuration:
- `Info.plist` - App Transport Security exceptions
- `MULTIPLAYER_PLAN.md` - Progress tracking

### Debug/Temporary:
- Debug counters and visual indicators
- Manual test buttons
- Comprehensive logging system

---

**Status**: ✅ **ROOT CAUSE IDENTIFIED AND UI WORKING**  
**Next**: Fix timing to complete Step 3 implementation