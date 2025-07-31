# API Route Analysis: iOS App vs Backend Routes

## Executive Summary

Analysis of iOS app API calls vs refactored backend routes reveals **critical mismatches** in the hint system and phrase fetching. The hint system appears to be **client-side now** (clues fetched with phrases), but there are structural mismatches between what iOS expects vs what backend provides.

## Key Findings

### ✅ Your Assumption is CORRECT
**The hint system is now client-side!** Evidence:
- iOS `PhrasePreview.PhraseData` includes `hint: String` (the clue text)
- iOS includes `hintStatus: HintStatus` with client-side hint management
- iOS includes `scorePreview: ScorePreview` for different hint levels
- Server provides clue with phrase, client manages hint levels 1-3 locally

### 🔴 Critical Mismatch Found
**Current backend `/api/phrases/for/:playerId` doesn't match iOS expectations:**

**iOS Expects (`PhrasePreview`):**
```json
{
  "success": true,
  "phrase": {
    "id": "string",
    "content": "string", 
    "hint": "string",
    "difficultyLevel": 1,
    "isGlobal": true,
    "hintStatus": { "hintsUsed": [], "nextHintLevel": 1, ... },
    "scorePreview": { "noHints": 100, "level1": 80, ... }
  },
  "timestamp": "string"
}
```

**Backend Currently Returns:**
```json
{
  "phrases": [{ ... }, { ... }],
  "count": 2,
  "timestamp": "string"
}
```

## Route Status Analysis

### 📊 WEB DASHBOARD ROUTES - Admin Interface Only  
**Status**: Web dashboard backend routes currently **DISABLED** in game server
| Route | File | Used By | Purpose |
|-------|------|---------|---------|
| `/monitoring` | `system.js` | Web Dashboard Frontend | Admin monitoring UI (HTML page) |
| `/contribute/:token` | `system.js` | Web Dashboard Frontend | Contribution form UI (HTML page) |
| `/api/stats` | `players.js` | Web Dashboard (monitoring.js) | Live system statistics for admin monitoring |
| `/api/players/online` | `players.js` | Web Dashboard (monitoring.js) | Online player list for admin monitoring |

### 🔗 LINK GENERATOR SERVICE ROUTES - Microservice (Port 3002)
**Status**: Active standalone service for contribution link management
| Route | Service | Purpose |
|-------|---------|---------|
| `GET /api/status` | Link Generator | Health check for service monitoring |
| `POST /api/links/generate` | Link Generator | Generate secure contribution links |
| `GET /api/links/validate/:token` | Link Generator | Validate contribution link tokens |

### 🗑️ DEFINITELY UNUSED - Safe to Remove from Game Server
| Route | File | Reason |
|-------|------|--------|
| `/api/config` | `system.js` | iOS uses `/api/config/levels` instead |
| `/api/admin/config` | `system.js` | Admin-only feature, no consumers found |
| `/api/phrases/global` | `phrases.js` | Not used by current iOS version |
| `/api/phrases/:phraseId/approve` | `phrases.js` | Admin-only feature, no consumers found |
| `/api/phrases/download/:playerId` | `phrases.js` | Offline feature not implemented in iOS |
| `/api/contribution/*` | `contributions.js` | **LEGACY** - Being replaced by Link Generator Service |
| `/api/leaderboards/:period` | `leaderboards.js` | iOS uses singular `/api/leaderboard/` |
| `/api/stats/global` | `leaderboards.js` | Admin/monitoring feature, no consumers found |
| `/api/scores/refresh` | `leaderboards.js` | Admin-only feature, no consumers found |

### ✅ HINT SYSTEM ROUTES - Confirmed Legacy (Phase 2 Complete)
| Route | iOS Usage | Status | Action Taken |
|-------|-----------|---------|--------------|
| `/api/phrases/:phraseId/hint` | `PhraseService.swift:104` | **LEGACY** | ✅ **iOS converted to client-side** |
| `/api/phrases/:phraseId/hints/status` | `NetworkManager.swift:362` | **LEGACY** | ✅ **iOS converted to client-side** |
| `/api/phrases/:phraseId/preview` | `NetworkManager.swift:403` | **LEGACY** | ✅ **iOS converted to client-side** |

**Investigation Results:**
- These routes exist only in legacy server (`/server/server.js`) - **NOT in current microservices backend**
- iOS app was calling missing routes, causing hint button to fail silently
- Hint system **IS** client-side with shelf illumination (`scene.showHint1()`, `scene.showHint2()`, `scene.showHint3()`)
- **Fix Applied**: Updated `HintButtonView.swift` to use only client-side logic for all phrases

### 🔴 CRITICAL MISSING - Need Implementation
| Route | iOS Usage | Action |
|-------|-----------|---------|
| `/api/phrases/:phraseId/complete` | `PhraseService.swift:138` | ✅ **Must implement** |
| `/api/leaderboard/:type/player/:playerId` | `LeaderboardService.swift:136` | ✅ **Must implement** |

### 🔧 STRUCTURAL MISMATCH - Need Backend Update
| Route | Issue | Action |
|-------|--------|--------|
| `/api/phrases/for/:playerId` | Returns array, iOS expects single phrase with hintStatus | 🔧 **Update structure** |

## Planned Actions

### Phase 1: Immediate Fixes (Critical) ✅ COMPLETED
1. ✅ **Fixed `/api/phrases/for/:playerId`** - Now returns single phrase with client-side `hintStatus` and `scorePreview`
   - **Change**: Returns `PhrasePreview` structure instead of `{ phrases: [], count: X }`
   - **Features**: Generated client-side hint system with 3 hint levels and score penalties
   - **Scoring**: Uses shared difficulty algorithm with 20%/40%/60% hint penalties
2. ✅ **Added `/api/phrases/:phraseId/complete`** - Complete endpoint for phrase completion
   - **Accepts**: `playerId`, `hintsUsed`, `completionTime`
   - **Returns**: `CompletionResult` with `finalScore`, `hintsUsed`, `completionTime`
   - **Features**: Calculates final score with hint penalties, marks phrase consumed, broadcasts completion
3. ✅ **Added `/api/leaderboard/:type/player/:playerId`** - Player ranking lookup
   - **Supports**: `daily`, `weekly`, `alltime` leaderboard types
   - **Returns**: Player's rank in specified leaderboard
   - **Validation**: UUID format validation and error handling

### Phase 2: Investigation (High Priority) ✅ COMPLETED
1. **✅ Analyzed phrase fetching system** - Documented quantities and frequency in `phrase-fetching-analysis.md`
   - **Findings**: Always 1 phrase delivered to iOS (from up to 10 fetched), on-demand + real-time push
2. **✅ Fixed hint system routes** - Converted iOS to fully client-side hint system
   - **Problem**: Routes `/api/phrases/:phraseId/hint`, `/hints/status`, `/preview` missing from microservices
   - **Solution**: Updated `HintButtonView.swift` to use client-side logic only
   - **Result**: Hint button now works with shelf illumination and database clues
3. **✅ Updated iOS app** - Removed server-side hint calls, uses database clues directly
4. **✅ Verified phrase completion flow** - Uses new `/api/phrases/:phraseId/complete` endpoint

### Phase 3: Cleanup (Medium Priority)
1. **Remove confirmed unused routes** from game server:
   - `/api/config` (iOS uses `/api/config/levels`)
   - `/api/admin/config` (no consumers)
   - `/api/phrases/global` (not used by iOS)
   - `/api/phrases/:phraseId/approve` (no consumers)
   - `/api/phrases/download/:playerId` (not implemented in iOS)
   - `/api/contribution/*` (legacy, replaced by Link Generator Service)
   - `/api/leaderboards/:period` (iOS uses singular form)
   - `/api/stats/global` (no consumers)
   - `/api/scores/refresh` (no consumers)
2. **Keep web dashboard routes** but decide if they should remain in game server or move to web dashboard service:
   - `/monitoring` and `/contribute/:token` (UI pages)
   - `/api/stats` and `/api/players/online` (used by web dashboard frontend)
3. **Document remaining routes** by consumer service (iOS vs Web Dashboard vs Link Generator)

### Phase 4: Optimization (Low Priority)
1. **Consider route versioning** (`/api/v1/`, `/api/v2/`)
2. **Add route usage analytics** to confirm which routes are actually called
3. **Consolidate duplicate functionality** (plural vs singular endpoints)

## Testing Strategy

### Before Removing Any Routes:
1. **Enable request logging** on all routes for 24-48 hours
2. **Test full iOS app flow** with current routes
3. **Check web dashboard functionality** if routes are used there
4. **Verify WebSocket events** don't depend on removed routes

### After Changes:
1. **Integration test** iOS app with updated backend
2. **Test hint system thoroughly** - verify client-side vs server-side behavior
3. **Test phrase completion flow** end-to-end
4. **Performance test** with simplified route structure

## Microservices Architecture Insights

### Current Service Distribution:
- **Game Server (port 3000)**: Core iOS API + Web Dashboard routes + Legacy contribution routes
- **Web Dashboard (port 3001)**: Admin frontend + Disabled backend routes  
- **Link Generator (port 3002)**: Active contribution link management service

### Key Architectural Issues:
1. **Route Duplication**: Web dashboard routes exist in both game server and web dashboard service
2. **Service Boundaries**: Game server hosts web dashboard UI (mixing concerns)
3. **Legacy Code**: Old contribution system coexists with new Link Generator Service
4. **Backend Overlap**: Web dashboard backend routes disabled but game server serves web dashboard frontend

## Recommendations

### Immediate Actions:
1. ✅ **Start with Phase 1** - Fix critical structural mismatches
2. 🔍 **Investigate hint routes** - Your assumption is likely correct but needs verification  
3. 📝 **Document route consumers** - Now completed with microservices analysis

### Long-term Strategy:
1. **Complete microservices separation**: Move web dashboard routes from game server to web dashboard service
2. **Enable web dashboard backend**: Activate disabled routes in web dashboard service
3. **Remove legacy contribution routes**: Complete migration to Link Generator Service
4. **Version APIs** to handle breaking changes gracefully
5. **Add automated route testing** to prevent future mismatches

---

**Next Steps:** Fix the `/api/phrases/for/:playerId` structure mismatch first, then investigate the hint system routes to confirm they can be removed.