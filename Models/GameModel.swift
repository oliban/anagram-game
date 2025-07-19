import Foundation
import SwiftData
import Combine

// Data structure for local phrases with clues
struct LocalPhrase {
    let content: String
    let clue: String?
    
    init(content: String, clue: String? = nil) {
        self.content = content
        self.clue = clue
    }
}

protocol MessageTileSpawner: AnyObject {
    func spawnMessageTile(message: String)
    func resetGame()
}

@Observable
class GameModel: ObservableObject {
    var currentSentence: String = ""
    var scrambledLetters: [String] = []
    var gameState: GameState = .playing
    var wordsCompleted: Int = 0
    var customPhraseInfo: String = ""
    
    // Phrase notification state
    private var notificationTimer: Timer?
    private var activeNotifications: Set<String> = [] // Track active notifications by sender name
    
    // Game scene reference for tile spawning
    weak var messageTileSpawner: MessageTileSpawner?
    
    // Hint system state
    var currentPhraseId: String? = nil
    var currentHints: [String] = []
    var currentScore: Int = 0
    var hintsUsed: Int = 0
    var phraseDifficulty: Int = 0
    
    // Player information
    var playerId: String? = nil
    var playerName: String? = nil
    var networkManager: NetworkManager? = nil
    
    private var localPhrases: [LocalPhrase] = []
    var currentCustomPhrase: CustomPhrase? = nil // Made public for LanguageTile access
    private var phraseQueue: [CustomPhrase] = [] // Queue for incoming phrases
    private var lobbyDisplayQueue: [CustomPhrase] = [] // Separate queue for lobby display only
    private var isStartingNewGame = false
    private var isCheckingPhrases = false
    private var isSkipping = false // Prevent concurrent skip operations
    
    // Computed property to get current language for LanguageTile display
    var currentLanguage: String {
        return currentCustomPhrase?.language ?? "en"
    }
    
    // Computed properties for phrase queue status (public for UI access)
    var waitingPhrasesCount: Int {
        return lobbyDisplayQueue.count
    }
    
    var waitingPhrasesSenders: [String] {
        return lobbyDisplayQueue.map { $0.senderName }
    }
    
    var hasWaitingPhrases: Bool {
        return !lobbyDisplayQueue.isEmpty
    }
    
    enum GameState {
        case playing
        case completed
        case loading
        case error
    }
    
    init() {
        loadSentences()
        Task { @MainActor in
            setupNetworkNotifications()
            await startNewGame()
        }
    }
    
    private func loadSentences() {
        guard let path = Bundle.main.path(forResource: "anagrams", ofType: "txt"),
              let content = try? String(contentsOfFile: path) else {
            gameState = .error
            return
        }
        
        localPhrases = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                // Parse pipe-separated format: "phrase|clue"
                let components = line.components(separatedBy: "|")
                if components.count == 2 {
                    let phrase = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let clue = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    return LocalPhrase(content: phrase, clue: clue.isEmpty ? nil : clue)
                } else {
                    // Backwards compatibility: treat as phrase-only
                    return LocalPhrase(content: line, clue: nil)
                }
            }
        
        if localPhrases.isEmpty {
            gameState = .error
        }
    }
    
    func startNewGame(isUserInitiated: Bool = false) async {
        
        // Debug: Log entry to startNewGame
        await sendDebugToServer("ENTERING_startNewGame: isUserInitiated=\(isUserInitiated)")
        
        // Clear notification tracking for new game session
        await MainActor.run {
            activeNotifications.removeAll()
            print("📢 NOTIFICATION: Cleared notification tracking for new game session")
        }
        
        // Prevent multiple concurrent calls
        guard !isStartingNewGame else {
            await sendDebugToServer("STARTGAME_BLOCKED: already starting new game")
            return
        }
        
        isStartingNewGame = true
        
        // First check for custom phrases
        await checkForCustomPhrases(isUserInitiated: isUserInitiated)
        
        // Reset flag on main thread
        await MainActor.run {
            self.isStartingNewGame = false
        }
    }
    
    @MainActor
    private func checkForCustomPhrases(isUserInitiated: Bool = false) async {
        // Prevent multiple simultaneous phrase checks
        guard !isCheckingPhrases else {
            await sendDebugToServer("PHRASE_CHECK_BLOCKED: already checking phrases")
            return
        }
        
        isCheckingPhrases = true
        gameState = .loading
        
        // Debug: Log entry to checkForCustomPhrases
        await sendDebugToServer("ENTERING_checkForCustomPhrases: isUserInitiated=\(isUserInitiated)")
        
        let networkManager = NetworkManager.shared
        
        // PRIORITY 1: Check phrase queue first
        if let queuedPhrase = getNextPhraseFromQueue() {
            print("📤 GAME: Using queued phrase: '\(queuedPhrase.content)' from \(queuedPhrase.senderName)")
            
            currentCustomPhrase = queuedPhrase
            currentSentence = queuedPhrase.content
            customPhraseInfo = "Custom phrase from \(queuedPhrase.senderName)"
            currentPhraseId = queuedPhrase.id
            
            // Mark as consumed on server
            let consumeSuccess = await networkManager.consumePhrase(phraseId: queuedPhrase.id)
            
            if consumeSuccess {
                print("✅ GAME: Successfully consumed queued phrase \(queuedPhrase.id)")
            } else {
                print("❌ GAME: Failed to consume queued phrase \(queuedPhrase.id)")
            }
        } else {
            // PRIORITY 2: Check for push-delivered phrase (for user-initiated actions)
            if isUserInitiated && networkManager.hasNewPhrase, let pushedPhrase = networkManager.lastReceivedPhrase {
                print("⚡ GAME: Using push-delivered phrase: '\(pushedPhrase.content)' (user-initiated)")
                
                currentCustomPhrase = pushedPhrase
                currentSentence = pushedPhrase.content
                customPhraseInfo = "Custom phrase from \(pushedPhrase.senderName)"
                currentPhraseId = pushedPhrase.id
                
                // Mark as consumed and clear the push flag
                let consumeSuccess = await networkManager.consumePhrase(phraseId: pushedPhrase.id)
                networkManager.hasNewPhrase = false
                
                if consumeSuccess {
                    print("✅ GAME: Successfully consumed push-delivered phrase \(pushedPhrase.id)")
                } else {
                    print("❌ GAME: Failed to consume push-delivered phrase \(pushedPhrase.id)")
                }
            } else {
                // FALLBACK: Fetch from server if no queued or push-delivered phrase
                print("🔍 GAME: No queued or push-delivered phrase, fetching from server")
                await sendDebugToServer("SERVER_FETCH_STARTING: fetching phrases from server")
                let customPhrases = await networkManager.fetchPhrasesForCurrentPlayer()
                
                // Debug: Log what we got from server
                await sendDebugToServer("SERVER_FETCH_RESULT: got \(customPhrases.count) phrases")
                
                if let firstPhrase = customPhrases.first {
                    print("✅ GAME: Got phrase from server: '\(firstPhrase.content)' (ID: \(firstPhrase.id))")
                    
                    currentCustomPhrase = firstPhrase
                    currentSentence = firstPhrase.content
                    customPhraseInfo = "Custom phrase from \(firstPhrase.senderName)"
                    currentPhraseId = firstPhrase.id
                    
                    // Mark the phrase as consumed on server IMMEDIATELY
                    let consumeSuccess = await networkManager.consumePhrase(phraseId: firstPhrase.id)
                    
                    if consumeSuccess {
                        print("✅ GAME: Successfully consumed server phrase \(firstPhrase.id)")
                    } else {
                        print("❌ GAME: Failed to consume server phrase \(firstPhrase.id)")
                    }
                } else {
                    print("🎯 GAME: No custom phrases available, using default sentence")
                    
                    // Debug: Log that we're using local phrases
                    await sendDebugToServer("USING_LOCAL_PHRASES: localPhrases.count=\(localPhrases.count)")
                    
                    // Use a random sentence from the default collection
                    guard !localPhrases.isEmpty else {
                        gameState = .error
                        isCheckingPhrases = false
                        return
                    }
                    
                    currentCustomPhrase = nil
                    let selectedPhrase = localPhrases.randomElement()?.content ?? "The cat sat on the mat"
                    currentSentence = selectedPhrase
                    customPhraseInfo = ""
                    // Create a session-based phrase ID for local sentences
                    currentPhraseId = "local-\(UUID().uuidString)"
                    print("🔍 DEBUG: Selected local phrase: '\(selectedPhrase)'")
                    print("🔍 DEBUG: Total local phrases available: \(localPhrases.count)")
                    
                    // Log calculated difficulty for debugging
                    let calculatedDifficulty = calculateDifficultyForPhrase(selectedPhrase)
                    print("🔍 DEBUG: LOCAL_PHRASE_SELECTED: '\(selectedPhrase)' calculated_difficulty=\(calculatedDifficulty)")
                    
                    // Send debug info to server
                    await sendDebugToServer("LOCAL_PHRASE_SELECTED: '\(selectedPhrase)' calculated_difficulty=\(calculatedDifficulty)")
                    
                    // CRITICAL: Set phraseDifficulty for local phrases
                    phraseDifficulty = calculatedDifficulty
                    await sendDebugToServer("LOCAL_PHRASE_DIFFICULTY_SET: phraseDifficulty=\(phraseDifficulty)")
                }
            }
        }
        
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
        
        // Reset hint state for new game
        currentHints = []
        currentScore = 0
        print("🔍 SCORE RESET: Score reset to 0 in startNewGame()")
        hintsUsed = 0
        
        // Set difficulty score based on phrase type
        if currentCustomPhrase != nil {
            // For custom phrases, use a default difficulty score or analyze the phrase
            phraseDifficulty = calculateDifficultyForPhrase(currentSentence)
        } else {
            // For default local phrases, calculate the actual difficulty score
            phraseDifficulty = calculateDifficultyForPhrase(currentSentence)
        }
        
        // Trigger scene reset after all game model updates are complete
        await MainActor.run {
            print("🔄 About to trigger scene reset - messageTileSpawner: \(messageTileSpawner != nil ? "connected" : "nil")")
            messageTileSpawner?.resetGame()
            print("🔄 Triggered scene reset from GameModel")
            // Reset flag to allow future phrase checks
            isCheckingPhrases = false
        }
        
        // Send debug messages after MainActor.run
        await sendDebugToServer("SCENE_RESET: messageTileSpawner is \(messageTileSpawner != nil ? "connected" : "nil")")
        await sendDebugToServer("SCENE_RESET: resetGame() called on scene")
    }
    
    private func scrambleLetters() {
        let letters = currentSentence.replacingOccurrences(of: " ", with: "")
        scrambledLetters = Array(letters).map { String($0) }.shuffled()
    }
    
    @MainActor
    func resetGame() {
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
        
        // Reset hint state
        currentHints = []
        currentScore = 0
        print("🔍 SCORE RESET: Score reset to 0 in resetGame()")
        hintsUsed = 0
        
        // Recalculate difficulty for current phrase
        phraseDifficulty = calculateDifficultyForPhrase(currentSentence)
    }
    
    func validateWordCompletion(formedWords: [String]) -> Bool {
        let expectedWords = currentSentence.components(separatedBy: " ")
        return formedWords.count == expectedWords.count && 
               Set(formedWords) == Set(expectedWords)
    }
    
    func checkWordFromTiles(at positions: [CGPoint]) -> String? {
        // This will be used by the physics scene to validate word formation
        // based on tile positions in the physics world
        return nil
    }
    
    func getExpectedWords() -> [String] {
        return currentSentence.components(separatedBy: " ")
    }
    
    @MainActor
    func completeGame() {
        gameState = .completed
        
        // Calculate score immediately based on local data
        currentScore = calculateLocalScore()
        print("✅ COMPLETION: Calculated local score: \(currentScore) points (difficulty: \(phraseDifficulty), hints: \(hintsUsed))")
        
        // Also complete phrase on server (async, no need to wait)
        if let phraseId = currentPhraseId {
            Task {
                let networkManager = NetworkManager.shared
                let result = await networkManager.completePhrase(phraseId: phraseId)
                print("🔍 SERVER COMPLETION: Server returned score \(result?.completion.finalScore ?? -1), client calculated \(currentScore)")
            }
        }
    }
    
    @MainActor
    private func calculateLocalScore() -> Int {
        // Use the same algorithm as preview and gameplay for consistency
        let language = currentCustomPhrase?.language ?? "en"
        let analysis = NetworkManager.analyzeDifficultyClientSide(phrase: currentSentence, language: language)
        let baseDifficulty = Int(analysis.score)
        
        print("🔍 SCORE: Recalculated base difficulty: \(baseDifficulty) (was stored as: \(phraseDifficulty))")
        
        guard baseDifficulty > 0 else { 
            print("❌ SCORE: baseDifficulty is \(baseDifficulty), returning 0")
            return 0 
        }
        
        var score = baseDifficulty
        
        if hintsUsed >= 1 { score = Int(round(Double(baseDifficulty) * 0.90)) }
        if hintsUsed >= 2 { score = Int(round(Double(baseDifficulty) * 0.70)) }
        if hintsUsed >= 3 { score = Int(round(Double(baseDifficulty) * 0.50)) }
        
        print("🔍 SCORE: After hints penalty (hints: \(hintsUsed)): \(score)")
        return score
    }
    
    @MainActor
    private func calculateDifficultyForPhrase(_ phrase: String) -> Int {
        // Use shared algorithm for consistency
        let language = currentCustomPhrase?.language ?? "en"
        let analysis = NetworkManager.analyzeDifficultyClientSide(phrase: phrase, language: language)
        
        print("🎯 GAME DIFFICULTY: Calculated \(analysis.score) for '\(phrase)' (\(language))")
        print("🔍 DEBUG: Phrase source - isCustom: \(currentCustomPhrase != nil), phraseId: \(currentPhraseId ?? "nil")")
        return Int(analysis.score)
    }
    
    func skipCurrentGame() async {
        print("🚀🚀🚀 SKIP BUTTON PRESSED - skipCurrentGame() CALLED 🚀🚀🚀")
        await sendDebugToServer("SKIP_BUTTON_PRESSED: Starting skipCurrentGame()")
        
        // Prevent concurrent skip operations to avoid race conditions
        guard !isSkipping else {
            await sendDebugToServer("SKIP_BLOCKED: Already skipping, ignoring concurrent request")
            print("⚠️ Skip already in progress, ignoring concurrent request")
            return
        }
        
        isSkipping = true
        print("🚀 Skip button pressed")
        
        // If we have a current custom phrase, skip it on the server
        if let customPhrase = currentCustomPhrase {
            await sendDebugToServer("SKIP_SERVER_PHRASE: Skipping custom phrase: \(customPhrase.content)")
            print("⏭️ Skipping custom phrase: \(customPhrase.content)")
            
            let networkManager = NetworkManager.shared
            await sendDebugToServer("SKIP_CALLING_SKIP_PHRASE: About to call skipPhrase")
            let skipSuccess = await networkManager.skipPhrase(phraseId: customPhrase.id)
            await sendDebugToServer("SKIP_PHRASE_RESULT: skipSuccess=\(skipSuccess)")
            
            if skipSuccess {
                print("✅ Successfully skipped phrase on server")
            } else {
                print("❌ Failed to skip phrase on server")
            }
            
            // Clear cached phrase data to prevent reuse
            await sendDebugToServer("SKIP_CLEARING_LOCAL_DATA: Clearing currentCustomPhrase")
            await MainActor.run {
                currentCustomPhrase = nil
                customPhraseInfo = ""
                currentPhraseId = nil
            }
            
            // Clear any cached phrases from NetworkManager
            await sendDebugToServer("SKIP_CLEARING_CACHE: About to call clearCachedPhrase")
            await networkManager.clearCachedPhrase()
            await sendDebugToServer("SKIP_CACHE_CLEARED: clearCachedPhrase completed")
        } else {
            await sendDebugToServer("SKIP_NO_CUSTOM_PHRASE: No custom phrase to skip")
        }
        
        // Start a new game regardless of skip result
        await sendDebugToServer("SKIP_STARTING_NEW_GAME: About to call startNewGame")
        print("🚀 Starting new game after skip")
        await startNewGame(isUserInitiated: true)
        
        // Reset skip flag to allow future skip operations
        isSkipping = false
        await sendDebugToServer("SKIP_COMPLETED: skipCurrentGame() finished")
    }
    
    func addHint(_ hint: String) {
        currentHints.append(hint)
        hintsUsed += 1
    }
    
    // Get the clue for the current local phrase (if available)
    func getCurrentLocalClue() -> String? {
        // Only provide clue for local phrases, not custom phrases
        guard currentCustomPhrase == nil else { return nil }
        
        // Find the current sentence in localPhrases and return its clue
        let currentPhrase = localPhrases.first { $0.content == currentSentence }
        return currentPhrase?.clue
    }
    
    // Send debug message to server
    private func sendDebugToServer(_ message: String) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/api/debug/log") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let logData = [
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "playerId": playerId ?? "unknown"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logData)
            request.httpBody = jsonData
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Debug logging failed: \(error)")
        }
    }
    
    // Network notification setup
    @MainActor
    private func setupNetworkNotifications() {
        // Watch for immediately received phrases
        let networkManager = NetworkManager.shared
        
        // Use Combine to observe justReceivedPhrase changes
        networkManager.$justReceivedPhrase
            .compactMap { $0 } // Only proceed if phrase is not nil
            .sink { [weak self] phrase in
                DispatchQueue.main.async {
                    self?.addPhraseToQueue(phrase)
                    // Clear the trigger so it doesn't fire again
                    networkManager.justReceivedPhrase = nil
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // Method to refresh phrase queue for lobby display
    func refreshPhrasesForLobby() async {
        let networkManager = NetworkManager.shared
        
        let phrases = await networkManager.fetchPhrasesForCurrentPlayer()
        
        await MainActor.run {
            print("📥 LOBBY: BEFORE REFRESH - lobbyDisplayQueue: \(lobbyDisplayQueue.count)")
            
            // Only update if the server data is different from what we have
            let serverPhraseIds = Set(phrases.map { $0.id })
            let currentPhraseIds = Set(lobbyDisplayQueue.map { $0.id })
            
            if serverPhraseIds != currentPhraseIds {
                print("📥 LOBBY: Server data changed, updating lobby display queue")
                lobbyDisplayQueue.removeAll()
                lobbyDisplayQueue.append(contentsOf: phrases)
            } else {
                print("📥 LOBBY: Server data unchanged, keeping current lobby display queue")
            }
            
            print("📥 LOBBY: AFTER REFRESH - lobbyDisplayQueue: \(lobbyDisplayQueue.count)")
            print("📥 LOBBY: Loaded \(phrases.count) phrases for lobby display")
            if !phrases.isEmpty {
                print("📥 LOBBY: Phrase senders: \(phrases.map { $0.senderName })")
            }
            print("📥 LOBBY: Queue status - hasWaitingPhrases: \(hasWaitingPhrases), waitingPhrasesCount: \(waitingPhrasesCount)")
        }
    }
    
    // Phrase queue management
    private func addPhraseToQueue(_ phrase: CustomPhrase) {
        phraseQueue.append(phrase)
        lobbyDisplayQueue.append(phrase) // Also add to lobby display queue
        print("📥 QUEUE: Added phrase to queue: '\(phrase.content)' from \(phrase.senderName) (Lobby: \(lobbyDisplayQueue.count))")
        
        // Show notification for the new phrase
        showPhraseNotification(senderName: phrase.senderName)
    }
    
    private func getNextPhraseFromQueue() -> CustomPhrase? {
        guard !phraseQueue.isEmpty else {
            return nil
        }
        
        let nextPhrase = phraseQueue.removeFirst()
        
        // Also remove from lobby display queue if it exists there
        if let index = lobbyDisplayQueue.firstIndex(where: { $0.id == nextPhrase.id }) {
            lobbyDisplayQueue.remove(at: index)
        }
        
        print("📤 QUEUE: Retrieved phrase from queue: '\(nextPhrase.content)' from \(nextPhrase.senderName) (Lobby: \(lobbyDisplayQueue.count))")
        return nextPhrase
    }
    
    // Phrase notification system
    private func showPhraseNotification(senderName: String) {
        // Check if we already have shown a notification from this sender during this game session
        guard !activeNotifications.contains(senderName) else {
            print("📢 NOTIFICATION: Skipping duplicate notification from \(senderName) - already shown this game session")
            return
        }
        
        // Add sender to active notifications for this game session
        activeNotifications.insert(senderName)
        
        // Clear any existing timer
        notificationTimer?.invalidate()
        
        // Spawn notification message tile
        let notificationMessage = "New phrase from \(senderName) incoming!"
        messageTileSpawner?.spawnMessageTile(message: notificationMessage)
        print("📢 NOTIFICATION: Spawned notification tile for \(senderName) (first time this game session)")
        
        // Update phrase info for any remaining UI that might need it
        customPhraseInfo = "Custom phrase from \(senderName)"
        
        // Schedule spawning of the persistent phrase info tile after 3 seconds
        notificationTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.notificationDisplayDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let currentPhrase = self.currentCustomPhrase {
                    let persistentMessage = "Custom phrase from \(currentPhrase.senderName)"
                    self.messageTileSpawner?.spawnMessageTile(message: persistentMessage)
                }
            }
        }
    }
}