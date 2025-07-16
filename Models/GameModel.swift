import Foundation
import SwiftData
import Combine

protocol MessageTileSpawner: AnyObject {
    func spawnMessageTile(message: String)
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
    
    private var sentences: [String] = []
    var currentCustomPhrase: CustomPhrase? = nil // Made public for LanguageTile access
    private var phraseQueue: [CustomPhrase] = [] // Queue for incoming phrases
    private var lobbyDisplayQueue: [CustomPhrase] = [] // Separate queue for lobby display only
    private var isStartingNewGame = false
    
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
        
        sentences = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if sentences.isEmpty {
            gameState = .error
        }
    }
    
    func startNewGame(isUserInitiated: Bool = false) async {
        
        // Clear notification tracking for new game session
        activeNotifications.removeAll()
        print("📢 NOTIFICATION: Cleared notification tracking for new game session")
        
        // Prevent multiple concurrent calls
        guard !isStartingNewGame else {
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
        gameState = .loading
        
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
                let customPhrases = await networkManager.fetchPhrasesForCurrentPlayer()
                
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
                    
                    // Use a random sentence from the default collection
                    guard !sentences.isEmpty else {
                        gameState = .error
                        return
                    }
                    
                    currentCustomPhrase = nil
                    currentSentence = sentences.randomElement() ?? "The cat sat on the mat"
                    customPhraseInfo = ""
                    // Create a session-based phrase ID for local sentences
                    currentPhraseId = "local-\(UUID().uuidString)"
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
            // For default local phrases, use a standard difficulty
            phraseDifficulty = 100 // Default score for local phrases
        }
    }
    
    private func scrambleLetters() {
        let letters = currentSentence.replacingOccurrences(of: " ", with: "")
        scrambledLetters = Array(letters).map { String($0) }.shuffled()
    }
    
    func resetGame() {
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
        
        // Reset hint state
        currentHints = []
        currentScore = 0
        print("🔍 SCORE RESET: Score reset to 0 in resetGame()")
        hintsUsed = 0
        phraseDifficulty = 0
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
        return Int(analysis.score)
    }
    
    func skipCurrentGame() async {
        print("🚀 Skip button pressed")
        
        // If we have a current custom phrase, skip it on the server
        if let customPhrase = currentCustomPhrase {
            print("⏭️ Skipping custom phrase: \(customPhrase.content)")
            let networkManager = NetworkManager.shared
            let skipSuccess = await networkManager.skipPhrase(phraseId: customPhrase.id)
            
            if skipSuccess {
                print("✅ Successfully skipped phrase on server")
            } else {
                print("❌ Failed to skip phrase on server")
            }
            
            // Clear cached phrase data to prevent reuse
            await MainActor.run {
                currentCustomPhrase = nil
                customPhraseInfo = ""
                currentPhraseId = nil
            }
            
            // Clear any cached phrases from NetworkManager
            await networkManager.clearCachedPhrase()
        }
        
        // Start a new game regardless of skip result
        print("🚀 Starting new game after skip")
        await startNewGame(isUserInitiated: true)
    }
    
    func addHint(_ hint: String) {
        currentHints.append(hint)
        hintsUsed += 1
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