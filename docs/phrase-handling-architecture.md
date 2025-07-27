# Phrase Handling Architecture - Anagram Game

## Overview
This document describes how phrases are fetched, managed, and delivered in the iOS Anagram Game app. The system uses a hybrid approach combining HTTP REST API calls for bulk fetching and WebSocket connections for real-time phrase delivery.

## Architecture Schematic

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   App Launch    │───▶│   Registration   │───▶│  First Game     │
│   ContentView   │    │                  │    │  startNewGame() │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PHRASE ACQUISITION FLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    HTTP GET                ┌──────────────────┐│
│  │   GameModel     │◄──────────────────────────▶│  NetworkManager  ││
│  │ startNewGame()  │  /api/phrases/for/{id}     │ fetchPhrasesFor  ││
│  │     L:131       │                            │  CurrentPlayer() ││
│  └─────────────────┘                            │      L:866       ││
│           │                                     └──────────────────┘│
│           ▼                                                         │
│  ┌─────────────────┐                                                │
│  │ Phrase Priority │                                                │
│  │   Selection     │                                                │
│  │                 │                                                │
│  │ 1. Targeted     │                                                │
│  │ 2. Global       │                                                │
│  │ 3. Local File   │                                                │
│  └─────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    REAL-TIME PHRASE DELIVERY                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    WebSocket              ┌──────────────────┐ │
│  │   GameModel     │◄──────────────────────────┤  NetworkManager  │ │
│  │                 │   "new-phrase" event      │                  │ │
│  │ • phraseQueue   │                           │ handleNewPhrase()│ │
│  │ • lobbyDisplay  │                           │      L:525       │ │
│  │   Queue         │                           │                  │ │
│  └─────────────────┘                           └──────────────────┘ │
│           ▲                                             │           │
│           │                                             ▼           │
│           │                                   ┌──────────────────┐ │
│           └───────────────────────────────────│ Immediate Notify │ │
│                                               │                  │ │
│                                               │ • lastReceived   │ │
│                                               │ • hasNewPhrase   │ │
│                                               │ • justReceived   │ │
│                                               └──────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      LOBBY MANAGEMENT                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    onAppear              ┌──────────────────┐ │
│  │   LobbyView     │───────────────────────▶  │   GameModel      │ │
│  │     L:54        │                          │refreshPhrasesFor │ │
│  │                 │                          │    Lobby()       │ │
│  │                 │◄─────────────────────────│     L:676        │ │
│  │                 │   Updated Phrase Lists   │                  │ │
│  └─────────────────┘                          └──────────────────┘ │
│                                                         │           │
│                                                         ▼           │
│                                               ┌──────────────────┐ │
│                                               │ Preserve Logic   │ │
│                                               │                  │ │
│                                               │ • Keep targeted  │ │
│                                               │   WebSocket      │ │
│                                               │   phrases        │ │
│                                               │ • Merge with     │ │
│                                               │   server fetch   │ │
│                                               └──────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow Details

### 1. App Startup Flow

**Location**: `ContentView.swift` → `GameModel.swift:131`

```swift
// After successful registration
Task { @MainActor in
    await gameModel.startNewGame()
}
```

### 2. Server Phrase Fetching 

**Location**: `NetworkManager.swift:866`

```swift
func fetchPhrasesForCurrentPlayer() async -> [CustomPhrase] {
    // HTTP GET: /api/phrases/for/{playerId}
    // Returns: Array of CustomPhrase objects
}
```

**API Endpoint**: `GET /api/phrases/for/:playerId`

### 3. Real-time Phrase Reception

**Location**: `NetworkManager.swift:494-525`

```swift
// WebSocket listener
socket.on("new-phrase") { [weak self] data, _ in
    self?.handleNewPhrase(data: data)
}

// Handler updates state immediately
private func handleNewPhrase(data: [Any]) {
    // Decode phrase, set notification flags
    self.lastReceivedPhrase = phrase
    self.hasNewPhrase = true
    self.justReceivedPhrase = phrase
}
```

### 4. Lobby Phrase Management

**Location**: `LobbyView.swift:54` → `GameModel.swift:676`

```swift
// LobbyView appears
.onAppear {
    Task {
        await loadInitialData() // Calls refreshPhrasesForLobby()
    }
}

// GameModel refresh logic
func refreshPhrasesForLobby() async {
    let phrases = await networkManager.fetchPhrasesForCurrentPlayer()
    
    // CRITICAL: Preserve targeted phrases from WebSocket
    let existingTargetedPhrases = phraseQueue.filter { $0.targetId != nil }
    
    // Merge and update queues
}
```

## Key Data Structures

### CustomPhrase Model
**Location**: `NetworkManager.swift:59`

```swift
struct CustomPhrase: Codable, Identifiable, Equatable {
    let id: String              // Unique phrase identifier
    let content: String         // The actual phrase to solve
    let senderId: String        // Who sent this phrase
    let targetId: String?       // Who it's for (nil = global)
    let createdAt: Date         // When phrase was created
    let isConsumed: Bool        // Whether phrase has been played
    let senderName: String      // Display name of sender
    let language: String        // Language code (default: "en")
}
```

### GameModel Phrase Collections
**Location**: `GameModel.swift`

```swift
class GameModel: ObservableObject {
    // Current game state
    var currentCustomPhrase: CustomPhrase?    // Active phrase being played
    var currentPhraseId: String?              // ID of current phrase
    
    // Phrase queues (managed in refreshPhrasesForLobby)
    var phraseQueue: [CustomPhrase]           // Available for gameplay
    var lobbyDisplayQueue: [CustomPhrase]     // Shown in lobby preview
    
    // Source tracking
    var phraseSource: String                  // "Server-Targeted", "Server-Global", "Local"
    var customPhraseInfo: String              // Display text for UI
}
```

### NetworkManager State
**Location**: `NetworkManager.swift`

```swift
class NetworkManager: ObservableObject {
    // Real-time phrase reception
    var lastReceivedPhrase: CustomPhrase?     // Most recent WebSocket phrase
    var hasNewPhrase: Bool                    // Flag for new phrase available
    var justReceivedPhrase: CustomPhrase?     // Triggers immediate notification
}
```

## Phrase Priority Logic

When starting a new game, phrases are selected in this priority order:

1. **Targeted Phrases** (`targetId != nil`)
   - Phrases sent specifically to this player
   - Source: `"Server-Targeted ({senderName})"`

2. **Global Phrases** (`targetId == nil`)
   - Phrases available to all players
   - Source: `"Server-Global"`

3. **Local Phrases** (fallback)
   - From bundled `anagrams.txt` file
   - Source: `"Local"`

## Communication Protocols

### HTTP REST API
- **Endpoint**: `GET /api/phrases/for/{playerId}`
- **Purpose**: Bulk phrase fetching
- **Timing**: App startup, lobby refresh, new game start
- **Response**: JSON array of CustomPhrase objects

### WebSocket Events
- **Event**: `"new-phrase"`
- **Purpose**: Real-time phrase delivery
- **Timing**: When another player sends a phrase
- **Payload**: Single CustomPhrase with sender metadata

## Integration Points

### App Lifecycle
1. **Launch**: ContentView initializes GameModel
2. **Registration**: Player registers, triggers first game
3. **Game Start**: Fetches phrases, selects by priority
4. **Lobby Navigation**: Refreshes phrase lists
5. **Real-time Updates**: WebSocket pushes new phrases

### Error Handling
- Network failures fall back to local phrases
- Invalid phrase data is logged and skipped
- WebSocket disconnections don't block gameplay

### Performance Considerations
- Phrases are cached locally in GameModel collections
- WebSocket updates merge with existing cached data
- No unnecessary refetches during active gameplay

---

*This architecture ensures players always have fresh, personalized content while maintaining smooth gameplay experience and real-time multiplayer interaction.*