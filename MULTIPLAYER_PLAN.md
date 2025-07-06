# Detailed Multiplayer Implementation Plan with Subtasks

## Overview
Adding multiplayer to the iOS Anagram Game with incremental, testable steps. Each step builds a complete feature that can be tested end-to-end before proceeding.

**Total Estimated Time: 5.5 hours across 8 steps**

---

## Step 1: Basic Server + iOS Connection (45 mins)

### Server Setup (25 mins)
**1.1 Project Initialization (5 mins)**
- [x] `npm init` and create package.json
- [x] Install: express, socket.io, nodemon, cors
- [x] Create folder structure: server.js, /routes, /models
- [x] Add start scripts to package.json

**1.2 Basic Express Server (10 mins)**
- [x] Create server.js with express setup
- [x] Add CORS middleware for iOS development
- [x] Create GET /api/status endpoint (returns {"status": "online"})
- [x] Add error handling middleware

**1.3 WebSocket Foundation (10 mins)**
- [x] Integrate Socket.io with express server
- [x] Handle client connect/disconnect events
- [x] Add basic logging for connections
- [x] Test with browser WebSocket client

### iOS Network Layer (20 mins)
**1.4 NetworkManager Class (10 mins)**
- [x] Create NetworkManager.swift as singleton
- [x] Add URLSession configuration
- [x] Implement testConnection() method hitting /api/status
- [x] Add proper error handling with Result<Success, Failure>

**1.5 WebSocket Client (5 mins)**
- [x] Add URLSessionWebSocketTask wrapper
- [x] Handle connection lifecycle (connect, disconnect)
- [x] Add connection status enum (connecting, connected, disconnected, error)

**1.6 Connection Status UI (5 mins)**
- [x] Add connection indicator to ContentView
- [x] Create simple circle: green=connected, red=disconnected, yellow=connecting
- [x] Add manual "Test Connection" button

**Testing Checkpoint**: Start server, run iOS app, confirm connection indicator works

---

## Step 2: Player Registration System (30 mins)

### Server Player Management (15 mins)
**2.1 In-Memory Player Store (5 mins)**
- [x] Create players Map to store connected players
- [x] Add player model: {id, name, socketId, connectedAt}
- [x] Handle player cleanup on disconnect

**2.2 Registration API (5 mins)**
- [x] POST /api/players/register endpoint
- [x] Validate player name (required, 2-20 chars, alphanumeric)
- [x] Return player ID and success status

**2.3 Player List & Events (5 mins)**
- [x] GET /api/players/online endpoint
- [x] WebSocket events: 'player-joined', 'player-left'
- [x] Broadcast player list updates to all clients

### iOS Player Interface (15 mins)
**2.4 Player Registration (8 mins)**
- [x] Create PlayerRegistrationView with text input
- [x] Add form validation (name length, characters)
- [x] Store registered player info in @AppStorage
- [x] Handle registration success/failure

**2.5 Online Players List (7 mins)**
- [x] Create OnlinePlayersView with List
- [x] Add real-time updates via WebSocket
- [x] Show player count and names
- [x] Add refresh capability

**Testing Checkpoint**: Register 2-3 players on different simulators, confirm they see each other

---

## Step 3: Basic Custom Phrase Feature (60 mins)

### Server Phrase System (30 mins)
**3.1 Phrase Storage (10 mins)**
- [ ] Create in-memory phrases array with model: {id, content, senderId, targetId, createdAt}
- [ ] Add phrase validation (2-6 words, no special chars)
- [ ] Implement phrase ID generation

**3.2 Phrase API Endpoints (15 mins)**
- [ ] POST /api/phrases - create new phrase
- [ ] Validate: content (required), targetId (valid player)
- [ ] GET /api/phrases/for/:playerId - get phrases for specific player
- [ ] Add phrase consumption (mark as delivered)

**3.3 Real-time Notifications (5 mins)**
- [ ] WebSocket event 'new-phrase' to target player
- [ ] Include phrase content and sender name
- [ ] Handle offline players (store for later delivery)

### iOS Phrase Creation & Integration (30 mins)
**3.4 Phrase Creation UI (15 mins)**
- [ ] Create PhraseCreationView as modal sheet
- [ ] Add text input with word count validation (2-6 words)
- [ ] Add target player picker (dropdown of online players)
- [ ] Send button with loading state and success feedback

**3.5 GameModel Integration (10 mins)**
- [ ] Add checkForCustomPhrases() method to GameModel
- [ ] Call API on game start to get pending phrases
- [ ] If custom phrase exists, use it instead of random selection
- [ ] Mark phrase as consumed after use

**3.6 Phrase Notifications (5 mins)**
- [ ] Add WebSocket listener for 'new-phrase' events
- [ ] Show toast notification: "New phrase from [PlayerName]!"
- [ ] Update phrase availability indicator

**Testing Checkpoint**: Player A sends "hello world" to Player B, Player B gets it in next game

---

## Step 4: Add Hints to Phrase System (30 mins)

### Server Hint Support (10 mins)
**4.1 Extend Phrase Model (5 mins)**
- [ ] Add hint field to phrase model
- [ ] Update POST /api/phrases to accept hint parameter
- [ ] Validate hint (optional, max 100 chars)

**4.2 API Response Updates (5 mins)**
- [ ] Include hint in GET /api/phrases/for/:playerId response
- [ ] Update WebSocket 'new-phrase' event to include hint

### iOS Hint Integration (20 mins)
**4.3 Hint Creation UI (8 mins)**
- [ ] Add hint text input to PhraseCreationView
- [ ] Add hint character counter (0/100)
- [ ] Make hint optional with placeholder text

**4.4 Hint Display in Game (7 mins)**
- [ ] Modify GameModel to store custom hint
- [ ] Update hint display in PhysicsGameView
- [ ] Show "(Custom hint from [PlayerName])" attribution

**4.5 Hint Validation (5 mins)**
- [ ] Add client-side hint validation
- [ ] Ensure hint doesn't contain the answer words
- [ ] Add hint quality feedback (too obvious, too vague)

**Testing Checkpoint**: Send phrase "cat dog" with hint "two animals", confirm hint shows correctly

---

## Step 5: "Available to All" Phrase Pool (30 mins)

### Server Community Phrases (15 mins)
**5.1 Extend Phrase Model (5 mins)**
- [ ] Add availableToAll boolean field
- [ ] Separate community phrases from targeted phrases
- [ ] Add community phrase filtering

**5.2 Community Phrase API (10 mins)**
- [ ] GET /api/phrases/random endpoint for community pool
- [ ] Exclude sender's own phrases from their random selection
- [ ] Add phrase popularity tracking (usage count)

### iOS Community Integration (15 mins)
**5.3 UI Updates (8 mins)**
- [ ] Add "Available to all players" checkbox to PhraseCreationView
- [ ] Show community contribution count to encourage sharing
- [ ] Add visual distinction for community vs targeted phrases

**5.4 Random Selection Logic (7 mins)**
- [ ] Update GameModel phrase loading to include community phrases
- [ ] Implement weighted selection (mix of original + community)
- [ ] Add "Community phrase by [PlayerName]" attribution

**Testing Checkpoint**: Mark phrase as community, confirm other players can get it randomly

---

## Step 6: Basic Quake System (45 mins)

### Server Quake Infrastructure (20 mins)
**6.1 Quake API (10 mins)**
- [ ] POST /api/quakes endpoint with senderId and targetId
- [ ] Add rate limiting (max 1 quake per 30 seconds per player)
- [ ] Validate target player exists and is different from sender

**6.2 Real-time Quake Delivery (10 mins)**
- [ ] WebSocket 'quake-incoming' event to target player
- [ ] Include sender name and timestamp
- [ ] Add quake intensity parameter (for future scaling)

### iOS Quake Integration (25 mins)
**6.3 Quake Sending UI (10 mins)**
- [ ] Add quake button to PhysicsGameView (earthquake icon)
- [ ] Create target player selection popup
- [ ] Add cooldown timer display (30 second countdown)
- [ ] Show "Quake sent!" confirmation

**6.4 Quake Reception (10 mins)**
- [ ] Add WebSocket listener for 'quake-incoming'
- [ ] Connect to existing earthquake system in PhysicsGameView
- [ ] Show "Quake from [PlayerName]!" notification
- [ ] Add haptic feedback for received quakes

**6.5 Quake Integration (5 mins)**
- [ ] Ensure quakes work during active gameplay
- [ ] Add visual effect for incoming quake (screen flash)
- [ ] Test quake doesn't interfere with game completion

**Testing Checkpoint**: Player A sends quake to Player B during game, B's game shakes immediately

---

## Step 7: Queued Quakes for Offline Players (30 mins)

### Server Offline Handling (15 mins)
**7.1 Pending Events System (10 mins)**
- [ ] Create pendingEvents array with model: {targetId, type, data, timestamp}
- [ ] Store quakes when target player is offline
- [ ] Add cleanup for old events (remove after 24 hours)

**7.2 Event Delivery on Reconnect (5 mins)**
- [ ] Check for pending events on player connection
- [ ] Deliver queued quakes with slight delay (2-3 seconds)
- [ ] Remove delivered events from pending queue

### iOS Offline Quake Handling (15 mins)
**7.3 Game Resume Detection (8 mins)**
- [ ] Add game resume detection in PhysicsGameView
- [ ] Check for pending quakes when game becomes active
- [ ] Handle multiple queued quakes (space them out)

**7.4 Delayed Quake Execution (7 mins)**
- [ ] Add timer-based quake delivery (not immediate on resume)
- [ ] Show "You missed a quake from [PlayerName]" if game wasn't active
- [ ] Add option to "catch up" on missed effects

**Testing Checkpoint**: Send quake to offline player, they get it 3 seconds after resuming game

---

## Step 8: Polish & Error Handling (45 mins)

### Server Reliability (20 mins)
**8.1 Input Validation & Security (10 mins)**
- [ ] Add comprehensive input validation for all endpoints
- [ ] Sanitize player names and phrase content
- [ ] Add request rate limiting (prevent spam)
- [ ] Add basic authentication tokens

**8.2 Error Handling & Logging (10 mins)**
- [ ] Add structured logging for all operations
- [ ] Implement graceful error responses
- [ ] Add server health check endpoint
- [ ] Handle database/storage errors properly

### iOS Production Readiness (25 mins)
**8.3 Network Error Handling (12 mins)**
- [ ] Handle server disconnection gracefully
- [ ] Add automatic reconnection with exponential backoff
- [ ] Show user-friendly error messages
- [ ] Maintain offline functionality for single-player

**8.4 User Experience Polish (8 mins)**
- [ ] Add loading states for all network operations
- [ ] Implement haptic feedback for multiplayer events
- [ ] Add sound effects for phrase/quake reception
- [ ] Create smooth animations for UI transitions

**8.5 Testing & Validation (5 mins)**
- [ ] Test with poor network conditions
- [ ] Verify memory usage and performance
- [ ] Test concurrent multiplayer actions
- [ ] Validate on different device sizes

**Final Testing**: Comprehensive multiplayer session with network interruptions

---

## Critical Decision Points

### Database Choice
**Development**: In-memory storage (faster iteration)
**Production**: SQLite file (persistence) or PostgreSQL (scalability)

### Authentication
**MVP**: Simple player names (no passwords)
**Future**: Apple ID integration or email-based accounts

### Server Hosting
**Development**: Local server on Mac
**Production**: Railway, Heroku, or DigitalOcean

### Testing Strategy
Each step has a clear testing checkpoint that validates the feature works end-to-end before proceeding to the next step. This ensures we can stop at any point and have working functionality.

---

## Integration with Existing Code

### Preserved Single-Player Functionality
- All current game mechanics remain unchanged
- Existing physics simulation stays completely local
- Original phrase loading from anagrams.txt continues to work
- No breaking changes to current save/load systems

### Extension Points
- GameModel extended for multiplayer state (backward compatible)
- PhysicsGameView enhanced with multiplayer UI overlays
- NetworkManager added as new singleton (no conflicts)
- Existing earthquake system reused for remote quakes

Ready to start with Step 1?