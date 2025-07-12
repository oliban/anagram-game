# Phrases Redesign Implementation Plan

## Overview
Transform anagram game from local anagrams.txt dependency to server-based phrase fetching with offline caching and progression system preparation.

## Progress Tracking
- **Started**: 2025-07-12
- **Current Phase**: Phase 2 - Remove Clue Length Restriction + Migrate anagrams.txt
- **Completed Phases**: Phase 1 (Write Tests First)
- **Total Time Spent**: 4 hours
- **Estimated Remaining**: 12.5-16.5 hours

### Phase Status Legend
- 🔄 **In Progress** - Currently working on this phase
- ✅ **Complete** - Phase finished and tested
- ⏸️ **Paused** - Phase started but temporarily stopped
- ❌ **Blocked** - Phase cannot proceed due to dependency
- ⏭️ **Skipped** - Phase not needed for current iteration

## Time Estimates (Total: ~16.5-20.5 hours)

---

## Phase 1: Write Tests First (TDD) - **4 hours** ✅

### 1.1 PhraseCache Tests (1.5 hours) ✅
- **File**: `Anagram GameTests/PhraseCacheTests.swift`
- **Status**: Complete
- **Started**: 2025-07-12 07:45
- **Completed**: 2025-07-12 07:52
- **Notes**: Comprehensive test suite covering cache initialization, adding phrases, played tracking, persistence, size management, and difficulty filtering 
- Test cache initialization (empty cache, valid storage)
- Test adding phrases (single, multiple, duplicates)
- Test played phrase tracking (mark played, get unplayed count, avoid repeats)
- Test cache persistence (save/load from UserDefaults)
- Test cache size management (30 phrase limit, oldest removal)
- Test difficulty filtering (store phrases with difficulty scores, filter by range)

### 1.2 Network Reachability Tests (45 minutes) ✅
- **File**: `Anagram GameTests/NetworkReachabilityTests.swift`
- **Status**: Complete
- **Started**: 2025-07-12 07:52
- **Completed**: 2025-07-12 07:57
- **Notes**: Comprehensive test suite with mock network monitor, testing online/offline detection, connectivity changes, connection types, notifications, and error handling 
- Test online/offline detection (mock NWPathMonitor)
- Test connectivity change notifications
- Test fetch behavior based on connection state

### 1.3 Phrase Selection Logic Tests (1 hour) ✅
- **File**: `Anagram GameTests/OfflinePhraseSystemTests.swift`
- **Status**: Complete
- **Started**: 2025-07-12 07:57
- **Completed**: 2025-07-12 08:05
- **Notes**: Comprehensive test suite covering online/offline phrase selection, difficulty-based filtering, cache management, error handling, and edge cases 
- Test online phrase selection (cache first, then server)
- Test offline phrase selection (cache only, no repeats)
- Test difficulty-based selection (fetch appropriate difficulty range)
- Test empty cache handling (online fallback, offline error state)
- Test phrase depletion scenarios (<10 phrases, 0 phrases)

### 1.4 Offline Progress Tests (45 minutes) ✅
- **File**: `Anagram GameTests/GameModelOfflineTests.swift`
- **Status**: Complete
- **Started**: 2025-07-12 08:05
- **Completed**: 2025-07-12 08:12
- **Notes**: Comprehensive test suite covering offline completion tracking, server sync, progress queue management, analytics, and error handling 
- Test completion tracking when offline
- Test score/hint storage for server sync
- Test progress queue management
- Test server sync when connection restored

---

## Phase 2: Remove Clue Length Restriction + Migrate anagrams.txt - **3 hours**

### 2.1 Remove 10-Character Clue Limitation (30 minutes)
- **File**: `Views/PhraseCreationView.swift`
- Remove minimum 10-character validation for clues
- Update UI placeholder text to remove "min 10 characters" reference
- Allow any non-empty clue (even single words like "Animals" or "Food")
- Update validation logic to only require non-empty clue

### 2.2 Create Migration Script (1.5 hours)
- **File**: `Scripts/migrate-anagrams.js`
- Read anagrams.txt content
- Generate meaningful clues for each phrase using AI/templates:
  - "be kind" → "Compassion"
  - "hello world" → "Programming greeting"
  - "time flies" → "Quick passage"
  - "lost keys" → "Misplaced items"
- Submit via POST /api/phrases/create with clue field
- Server calculates difficulty automatically

### 2.3 Execute Migration (30 minutes)
- Run migration script
- Verify all phrases in database with clues
- Test phrase fetching includes migrated content

### 2.4 Verification Script (1 hour)
- **File**: `Scripts/verify-migration.js`
- Query database for all migrated phrases
- Verify clues exist and are meaningful
- Check difficulty scores calculated correctly
- Generate migration success report

---

## Phase 3: Remove anagrams.txt System - **1 hour**

### 3.1 Clean GameModel (30 minutes)
- Delete `loadSentences()` method (GameModel.swift:75-89)
- Remove fallback logic (GameModel.swift:179-190)
- Update `init()` to remove loadSentences() call
- Remove sentences array property

### 3.2 Remove Files (30 minutes)
- Delete `Resources/anagrams.txt` (AFTER migration verified)
- Remove anagrams.txt from Xcode project.pbxproj
- Clean build to verify no references remain

---

## Phase 4: Create Data Models (Progression-Ready) - **1.5 hours**

### 4.1 Player Level System (45 minutes)
- **File**: `Models/PlayerLevel.swift`
- `PlayerLevel` struct with level, minDifficulty, maxDifficulty
- `DifficultyRange` struct for min/max bounds
- `getCurrentPlayerLevel()` method (returns level 1 for now)
- `getDifficultyRange()` method mapping level to difficulty

### 4.2 Cached Phrase Model (45 minutes)
- **File**: `Models/CachedPhrase.swift`
- Extend CustomPhrase with difficulty score and playedAt timestamp
- Codable implementation for UserDefaults storage
- Equality and hashing for Set operations

---

## Phase 5: Offline Phrase Cache System - **3 hours**

### 5.1 PhraseCache Class (2 hours)
- **File**: `Models/PhraseCache.swift`
- UserDefaults-based JSON storage
- Methods: save, load, addPhrases, markAsPlayed, getUnplayedCount
- Difficulty filtering for progression readiness
- Thread-safe operations with proper error handling
- 30 phrase limit with oldest removal

### 5.2 Integration with GameModel (1 hour)
- Add PhraseCache instance to GameModel
- Update phrase selection to use cache first
- Handle empty cache scenarios
- Track played phrases to avoid repeats

---

## Phase 6: Network Reachability - **1.5 hours**

### 6.1 Reachability Manager (1 hour)
- **File**: `Models/ReachabilityManager.swift`
- NWPathMonitor implementation
- Observable connectivity state
- Notification system for connection changes

### 6.2 NetworkManager Integration (30 minutes)
- Add isOnline property to NetworkManager
- Connect reachability changes to cache refresh
- Handle offline gracefully in existing methods

---

## Phase 7: Smart Phrase Fetching Logic - **2.5 hours**

### 7.1 Update Server API (1 hour)
- **Server route**: Modify `/api/phrases/for/:playerId`
- Add query params: minDifficulty, maxDifficulty
- Include global phrases (migrated anagrams) in results
- Maintain backward compatibility
- Filter by difficulty range in database query

### 7.2 iOS Fetching Logic (1.5 hours)
- Update `fetchPhrasesForCurrentPlayer()` for difficulty ranges
- App launch: fetch 30 phrases within player's level
- During play: check cache size, fetch if <10 unplayed phrases
- Random selection from appropriate difficulty range
- Proper error handling and fallbacks

---

## Phase 8: Offline Progress Tracking - **2 hours**

### 8.1 OfflineProgress Model (1 hour)
- **File**: `Models/OfflineProgress.swift`
- Store completed phrases, scores, hints used
- Queue for server synchronization
- Persistent storage with UserDefaults

### 8.2 GameModel Integration (1 hour)
- Update `completeGame()` for offline tracking
- Sync queue when connection restored
- Handle sync conflicts and failures
- Clear synced items from queue

---

## Phase 9: Handle "No Phrases" State - **1 hour**

### 9.1 Empty Cache Handling (30 minutes)
- Add isEmpty checks in phrase selection
- Spawn "No more phrases available" message tile
- Graceful degradation when cache depleted

### 9.2 UI Updates (30 minutes)
- Update lobby view to show phrase availability
- Add cache status indicators
- Handle offline state messaging

---

## Phase 10: Integration Testing - **2 hours**

### 10.1 Multi-Simulator Testing (1 hour)
- Deploy to both iPhone 15 simulators
- Test complete online/offline flow
- Verify cache refresh scenarios
- Test network state changes

### 10.2 Edge Case Testing (1 hour)
- Server down scenarios
- Corrupt cache handling
- No internet on first launch
- Performance testing (cache load times)

---

## Critical Requirements Checklist

### Clue System Compliance
- ✅ All migrated phrases MUST have meaningful clues
- ✅ Remove arbitrary 10-character minimum (allow concise clues)
- ✅ Use existing 3-tier hint system (word count, first letters, clue)
- ✅ Maintain clue persistence after Hint 3 used

### Data Integrity
- ✅ Zero data loss during migration
- ✅ Verify all anagrams.txt phrases in database
- ✅ Proper difficulty scoring server-side
- ✅ Include all CustomPhrase fields in cache

### Performance
- ✅ Cache first, then server strategy
- ✅ 30 phrase cache with <10 phrase refresh trigger
- ✅ Thread-safe cache operations
- ✅ Efficient UserDefaults JSON storage

### Progression Readiness
- ✅ Difficulty filtering infrastructure
- ✅ Player level system scaffolding
- ✅ Server API supports difficulty ranges
- ✅ Easy progression system integration later

---

## Success Criteria
1. **Zero anagrams.txt dependencies** - complete removal
2. **Seamless offline play** - 30 cached phrases, smart fetching
3. **All phrases have clues** - meaningful, 10+ characters
4. **No repeated phrases** - proper tracking online/offline
5. **Progression ready** - difficulty filtering works
6. **Robust testing** - comprehensive test coverage
7. **Performance maintained** - fast loading, efficient caching

## Next Steps After Completion
- Add actual progression system (XP, level up UI)
- Implement user preferences for difficulty
- Add phrase favorites/bookmarking
- Enhanced offline analytics

---

**REMINDER**: Follow CLAUDE.md workflow - research first, plan verified, implement with quality, test on both simulators, await feedback before proceeding.