# Phrase Fetching System Analysis

## Investigation Date
2025-07-31

## Question Analyzed
"How many phrases are fetched each time?" and "Explain to me when new phrases are fetched."

## Key Findings

### Phrase Fetching Quantities

**1. Targeted Phrases: Up to 10 phrases per fetch**
- **Database Query**: `LIMIT 10` in `DatabasePhrase.getPhrasesForPlayer()` (DatabasePhrase.js:255)
- **Server Logic**: Fetches up to 10 targeted phrases for performance/caching
- **iOS Consumption**: Only uses the first phrase via `customPhrases.first`
- **Efficiency**: Server prefetches more than needed to reduce round trips

**2. Global Phrases: 1 phrase per fetch**
- **Database Query**: `LIMIT 10` available but endpoint calls `getGlobalPhrases(1, 0, ...)` (phrases.js:470) 
- **Server Logic**: Fetches exactly 1 global phrase when no targeted phrases available
- **iOS Consumption**: Single phrase returned in array format for compatibility

### iOS Response Format Requirements

**Critical Compatibility Requirement:**
iOS NetworkManager expects array format `{ phrases: [...] }` at NetworkManager.swift:212-218:

```swift
if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let phrasesData = jsonResponse["phrases"] {
    let phrases = try JSONDecoder().decode([CustomPhrase].self, from: jsonData)
    return phrases
}
```

**Actual Usage Pattern:**
- Server returns: `{ phrases: [phrase1, phrase2, ...], count: X }`
- iOS consumes: Always uses `phrases.first` (only the first phrase)
- Result: **1 phrase delivered to iOS** regardless of fetch quantity

### Phrase Fetching Frequency & Triggers

Based on LobbyView.swift analysis, phrases are fetched at these triggers:

**1. On-Demand Fetching:**
- **Lobby Load**: `loadCustomPhrases()` called during initial lobby data load (LobbyView.swift:490)
- **Pull-to-Refresh**: User pulls to refresh lobby data (LobbyView.swift:67-68)
- **Game Return**: Returning from game triggers `refreshData()` (LobbyView.swift:86-88)

**2. Real-Time Push Notifications:**
- **WebSocket Events**: `new-phrase` events pushed via Socket.IO
- **No Polling**: No periodic timers for phrase fetching (relies on WebSocket push)

**3. Game Flow Triggers:**
- **New Game Start**: When starting a new game
- **Phrase Skip**: When user skips current phrase
- **Phrase Completion**: After completing a phrase (may trigger prefetch)

### System Architecture Summary

**Fetching Strategy:**
- **Background Prefetching**: Server fetches more phrases than immediately needed
- **Single-Phrase Consumption**: iOS always processes one phrase at a time
- **Push-Based Updates**: Real-time notifications reduce polling need
- **On-Demand Refresh**: User-initiated refresh ensures fresh content

**Performance Optimization:**
- Server maintains 10-phrase buffer for targeted phrases
- Client-side caching reduces redundant API calls  
- WebSocket notifications eliminate polling overhead
- Single phrase processing keeps UI responsive

## Final Answer

**Quantity**: Always **1 phrase** delivered to iOS app
- From up to 10 targeted phrases fetched (uses first)
- Or 1 global phrase fetched (when no targeted available)

**Frequency**: **On-demand + Real-time push**
- Lobby load, refresh, game return (user-initiated)
- WebSocket `new-phrase` events (server-initiated)
- No periodic polling or background fetching

**Architecture**: Efficient server-side prefetching with client-side single-phrase consumption pattern.

---

*This analysis confirms the phrase system is optimized for performance with background prefetching while maintaining simple single-phrase consumption for the iOS client.*