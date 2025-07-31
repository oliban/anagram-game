import Foundation
import SwiftData
import Combine
import QuartzCore

// Data structure for local phrases with clues
struct LocalPhrase {
    let content: String
    let clue: String?
    
    init(content: String, clue: String? = nil) {
        self.content = content
        self.clue = clue
    }
}

// Level system configuration structure
struct SkillLevel: Codable {
    let id: Int
    let title: String
    let pointsRequired: Int
    let maxDifficulty: Int
}

struct LevelMilestone: Codable {
    let level: Int
    let bonus: Int
    let description: String
}

struct LevelConfig: Codable {
    let version: String
    let progressionMultiplier: Double
    let baseDifficultyPerLevel: Int
    let skillLevels: [SkillLevel]
    let milestones: [LevelMilestone]
    
    static let `default` = LevelConfig(
        version: "2.0.0",
        progressionMultiplier: 1.3,
        baseDifficultyPerLevel: 50,
        skillLevels: [
            SkillLevel(id: 0, title: "non-existent", pointsRequired: 0, maxDifficulty: 0),
            SkillLevel(id: 1, title: "disastrous", pointsRequired: 100, maxDifficulty: 50)
        ],
        milestones: []
    )
    
    /// Get current skill level based on total points
    func getSkillLevel(for points: Int) -> SkillLevel {
        let level = skillLevels
            .sorted { $0.pointsRequired > $1.pointsRequired }
            .first { points >= $0.pointsRequired } ?? skillLevels.first!
        return level
    }
    
    /// Calculate progress to next skill level (0.0 to 1.0)
    func getProgressToNext(for points: Int) -> Double {
        let currentLevel = getSkillLevel(for: points)
        
        guard let nextLevel = skillLevels.first(where: { $0.id == currentLevel.id + 1 }) else {
            return 1.0 // Already at max level
        }
        
        let pointsInCurrentLevel = points - currentLevel.pointsRequired
        let pointsNeededForNext = nextLevel.pointsRequired - currentLevel.pointsRequired
        
        return min(1.0, max(0.0, Double(pointsInCurrentLevel) / Double(pointsNeededForNext)))
    }
    
    /// Get the next skill level title, or nil if at max level
    func getNextSkillLevel(for points: Int) -> SkillLevel? {
        let currentLevel = getSkillLevel(for: points)
        return skillLevels.first { $0.id == currentLevel.id + 1 }
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
    
    // Level system configuration (fetched from server)
    var levelConfig: LevelConfig = LevelConfig.default // Made public for UI access
    private var previousSkillLevelId: Int = 0 // Track previous skill level for level-up detection
    
    var playerTotalScore: Int = 0 {
        didSet {
            // Check for skill level up before persisting
            let newSkillLevel = levelConfig.getSkillLevel(for: playerTotalScore)
            if newSkillLevel.id > previousSkillLevelId {
                handleSkillLevelUp(from: previousSkillLevelId, to: newSkillLevel.id, newTitle: newSkillLevel.title)
                previousSkillLevelId = newSkillLevel.id
            }
            
            // Persist total score to UserDefaults when it changes
            if let playerId = playerId {
                UserDefaults.standard.set(playerTotalScore, forKey: "totalScore_\(playerId)")
                print("💾 PERSISTENCE: Saved total score \(playerTotalScore) for player \(playerId)")
            }
        }
    }
    
    // Skill level system computed properties
    var currentSkillLevel: SkillLevel {
        return levelConfig.getSkillLevel(for: playerTotalScore)
    }
    
    var progressToNextSkillLevel: Double {
        return levelConfig.getProgressToNext(for: playerTotalScore)
    }
    
    var nextSkillLevel: SkillLevel? {
        return levelConfig.getNextSkillLevel(for: playerTotalScore)
    }
    
    // Legacy computed property for backward compatibility
    var currentLevel: Int {
        return currentSkillLevel.id
    }
    
    // Level-up animation state
    var isLevelingUp: Bool = false
    
    private var localPhrases: [LocalPhrase] = []
    var currentCustomPhrase: CustomPhrase? = nil // Made public for LanguageTile access
    private var phraseQueue: [CustomPhrase] = [] // Queue for incoming phrases
    private var lobbyDisplayQueue: [CustomPhrase] = [] // Separate queue for lobby display only
    private var isStartingNewGame = false
    private var isCheckingPhrases = false
    private var isSkipping = false // Prevent concurrent skip operations
    private var currentPhraseSource: String = "Unknown"
    
    // Computed property to get current language for LanguageTile display
    var currentLanguage: String {
        return currentCustomPhrase?.language ?? "en"
    }
    
    // Public getter for current phrase source (for debug tile)
    var debugPhraseSource: String {
        return currentPhraseSource
    }
    
    // Computed properties for phrase queue status (public for UI access)
    // Only count targeted phrases (sent by other players), not global fallback phrases
    var waitingPhrasesCount: Int {
        return lobbyDisplayQueue.filter { $0.targetId != nil }.count
    }
    
    var waitingPhrasesSenders: [String] {
        return lobbyDisplayQueue.filter { $0.targetId != nil }.map { $0.senderName }
    }
    
    var hasWaitingPhrases: Bool {
        return lobbyDisplayQueue.contains { $0.targetId != nil }
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
            // Load level configuration from server
            await loadLevelConfig()
            // Remove automatic startNewGame() - let it be triggered after registration
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
        await DebugLogger.shared.sendToServer("ENTERING_startNewGame: isUserInitiated=\(isUserInitiated)")
        
        // Clear notification tracking for new game session
        await MainActor.run {
            activeNotifications.removeAll()
            print("📢 NOTIFICATION: Cleared notification tracking for new game session")
        }
        
        // Prevent multiple concurrent calls
        guard !isStartingNewGame else {
            await DebugLogger.shared.sendToServer("STARTGAME_BLOCKED: already starting new game")
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
            await DebugLogger.shared.sendToServer("PHRASE_CHECK_BLOCKED: already checking phrases")
            return
        }
        
        isCheckingPhrases = true
        gameState = .loading
        
        // Debug: Log entry to checkForCustomPhrases
        await DebugLogger.shared.sendToServer("ENTERING_checkForCustomPhrases: isUserInitiated=\(isUserInitiated)")
        
        let networkManager = NetworkManager.shared
        var phraseSource = "Unknown"
        
        // Use phrases already loaded in the lobby
        if let queuedPhrase = getNextPhraseFromQueue() {
            // DEBUG: Log the targetId value for debugging
            print("🐛 DEBUG: Queue phrase targetId = '\(queuedPhrase.targetId ?? "nil")' for phrase from \(queuedPhrase.senderName)")
            
            // Distinguish between targeted custom phrases and global phrases
            if queuedPhrase.targetId != nil {
                phraseSource = "Targeted (\(queuedPhrase.senderName))"
                customPhraseInfo = "Custom phrase from \(queuedPhrase.senderName)"
            } else {
                phraseSource = "Global"
                customPhraseInfo = "" // No sender info for global phrases
            }
            print("📤 GAME: Using cached server phrase: '\(queuedPhrase.content)' from \(queuedPhrase.senderName)")
            
            currentCustomPhrase = queuedPhrase
            currentSentence = queuedPhrase.content
            currentPhraseId = queuedPhrase.id
            
            // No need to consume phrases anymore - we're using pre-loaded batches
            print("📤 GAME: Using pre-loaded phrase \(queuedPhrase.id) from queue")
        } else {
            // PRIORITY 2: Check for push-delivered phrase (for user-initiated actions)
            if isUserInitiated && networkManager.hasNewPhrase, let pushedPhrase = networkManager.lastReceivedPhrase {
                // Distinguish between targeted and global push-delivered phrases
                if pushedPhrase.targetId != nil {
                    phraseSource = "Push-Targeted (\(pushedPhrase.senderName))"
                    customPhraseInfo = "Custom phrase from \(pushedPhrase.senderName)"
                } else {
                    phraseSource = "Push-Global"
                    customPhraseInfo = "" // No sender info for global phrases
                }
                print("⚡ GAME: Using push-delivered phrase: '\(pushedPhrase.content)' (user-initiated)")
                
                currentCustomPhrase = pushedPhrase
                currentSentence = pushedPhrase.content
                currentPhraseId = pushedPhrase.id
                
                // Clear the push flag
                networkManager.hasNewPhrase = false
                print("📤 GAME: Using push-delivered phrase \(pushedPhrase.id)")
            } else {
                // FALLBACK: Use local phrases if no server phrases available
                phraseSource = "Local-File"
                print("🎯 GAME: No custom phrases available, using local file sentence")
                
                // Debug: Log that we're using local phrases
                await DebugLogger.shared.sendToServer("USING_LOCAL_PHRASES: localPhrases.count=\(localPhrases.count)")
                
                // Use a random sentence from the default collection
                guard !localPhrases.isEmpty else {
                    gameState = .error
                    isCheckingPhrases = false
                    return
                }
                
                currentCustomPhrase = nil
                
                // Filter local phrases by current level (same logic as server filtering)
                let maxDifficulty = currentSkillLevel.maxDifficulty
                let levelAppropriatePhrases = localPhrases.filter { phrase in
                    let difficultyAnalysis = NetworkManager.analyzeDifficultyClientSide(phrase: phrase.content, language: "en")
                    return difficultyAnalysis.score <= Double(maxDifficulty)
                }
                
                print("🎯 LOCAL_PHRASE_FILTER: Level \(currentLevel), max difficulty: \(maxDifficulty)")
                print("🎯 LOCAL_PHRASE_FILTER: Filtered \(localPhrases.count) phrases to \(levelAppropriatePhrases.count) level-appropriate phrases")
                
                // Select from level-appropriate phrases, fallback to all if none match
                let phrasesToChooseFrom = levelAppropriatePhrases.isEmpty ? localPhrases : levelAppropriatePhrases
                let selectedPhrase = phrasesToChooseFrom.randomElement()?.content ?? "The cat sat on the mat"
                
                // Debug the selected local phrase
                let difficultyAnalysis = NetworkManager.analyzeDifficultyClientSide(phrase: selectedPhrase, language: "en")
                print("🔍 LOCAL_PHRASE_DEBUG: Selected local phrase '\(selectedPhrase)'")
                print("🔍 LOCAL_PHRASE_DEBUG: Difficulty score: \(difficultyAnalysis.score)")
                print("🔍 LOCAL_PHRASE_DEBUG: Used filtered list: \(!levelAppropriatePhrases.isEmpty)")
                await DebugLogger.shared.sendToServer("LOCAL_PHRASE_DEBUG: phrase='\(selectedPhrase)', difficulty=\(difficultyAnalysis.score), filtered=\(!levelAppropriatePhrases.isEmpty)")
                
                currentSentence = selectedPhrase
                customPhraseInfo = ""
                
                // Use a local ID for local phrases
                currentPhraseId = "local-\(UUID().uuidString)"
                
                print("🔍 DEBUG: Selected local phrase: '\(selectedPhrase)' with ID: \(currentPhraseId ?? "none")")
                print("🔍 DEBUG: Total local phrases available: \(localPhrases.count)")
                
                // Log calculated difficulty for debugging
                let calculatedDifficulty = calculateDifficultyForPhrase(selectedPhrase)
                print("🔍 DEBUG: LOCAL_PHRASE_SELECTED: '\(selectedPhrase)' calculated_difficulty=\(calculatedDifficulty)")
                
                // Send debug info to server
                await DebugLogger.shared.sendToServer("LOCAL_PHRASE_SELECTED: '\(selectedPhrase)' calculated_difficulty=\(calculatedDifficulty)")
                
                // CRITICAL: Set phraseDifficulty for local phrases
                phraseDifficulty = calculatedDifficulty
                await DebugLogger.shared.sendToServer("LOCAL_PHRASE_DIFFICULTY_SET: phraseDifficulty=\(phraseDifficulty)")
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
        if let customPhrase = currentCustomPhrase {
            // For custom phrases, use server-provided difficulty for consistency
            phraseDifficulty = customPhrase.difficultyLevel
            print("🎯 GAME DIFFICULTY: Using server difficulty \(phraseDifficulty) for '\(currentSentence)'")
        } else {
            // For default local phrases, calculate the actual difficulty score
            phraseDifficulty = calculateDifficultyForPhrase(currentSentence)
            print("🎯 GAME DIFFICULTY: Calculated local difficulty \(phraseDifficulty) for '\(currentSentence)'")
        }
        
        // Trigger scene reset after all game model updates are complete
        await MainActor.run {
            print("🔄 About to trigger scene reset - messageTileSpawner: \(messageTileSpawner != nil ? "connected" : "nil")")
            messageTileSpawner?.resetGame()
            print("🔄 Triggered scene reset from GameModel")
            
            // Store phrase source for later spawning in resetGame
            currentPhraseSource = phraseSource
            print("🐛 Stored phrase source: \(phraseSource) for debug tile spawning")
            
            // Spawn "local" information tile if this is a local phrase
            if phraseSource == "Local-File" {
                messageTileSpawner?.spawnMessageTile(message: "local")
                print("📍 LOCAL: Spawned 'local' information tile for anagrams.txt phrase")
            }
            
            // Reset flag to allow future phrase checks
            isCheckingPhrases = false
        }
        
        // Send debug messages after MainActor.run
        await DebugLogger.shared.sendToServer("SCENE_RESET: messageTileSpawner is \(messageTileSpawner != nil ? "connected" : "nil")")
        await DebugLogger.shared.sendToServer("SCENE_RESET: resetGame() called on scene")
    }
    
    // Called when messageTileSpawner connection is established
    @MainActor
    func onMessageTileSpawnerConnected() {
        print("🔗 messageTileSpawner connection established")
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
        if let customPhrase = currentCustomPhrase {
            // For custom phrases, use server-provided difficulty for consistency
            phraseDifficulty = customPhrase.difficultyLevel
            print("🎯 GAME DIFFICULTY: Using server difficulty \(phraseDifficulty) for '\(currentSentence)' in resetGame")
        } else {
            // For default local phrases, calculate the actual difficulty score
            phraseDifficulty = calculateDifficultyForPhrase(currentSentence)
        }
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
        
        // Update total score immediately for UI feedback
        let oldTotalScore = playerTotalScore
        playerTotalScore += currentScore
        print("🏆 TOTAL SCORE: Updated from \(oldTotalScore) to \(playerTotalScore) (+\(currentScore))")
        
        // Complete phrase on server (critical for leaderboard updates)
        if let phraseId = currentPhraseId {
            print("🔍 SERVER_COMPLETION: Attempting to complete phraseId: '\(phraseId)' with \(hintsUsed) hints")
            Task {
                let networkManager = NetworkManager.shared
                if let result = await networkManager.completePhrase(phraseId: phraseId, hintsUsed: hintsUsed) {
                    if result.success {
                        print("✅ SERVER COMPLETION: Success! Server score: \(result.completion.finalScore), client: \(currentScore)")
                        
                        // Refresh total score to get server's accurate total
                        Task { @MainActor in
                            await refreshTotalScoreFromServer()
                        }
                    } else {
                        print("❌ SERVER COMPLETION: Server reported failure")
                    }
                } else {
                    print("❌ SERVER COMPLETION: No result returned (network error or server issue)")
                    print("⚠️  LEADERBOARD: Score may not be updated due to server error")
                }
            }
        } else {
            print("⚠️  SERVER COMPLETION: No phraseId - server won't be notified")
        }
    }
    
    // MARK: - Centralized Hint Penalty Logic
    
    /// Apply hint penalty to a base score - SINGLE SOURCE OF TRUTH
    static func applyHintPenalty(baseScore: Int, hintsUsed: Int) -> Int {
        guard baseScore > 0 else { return 0 }
        
        var score = baseScore
        if hintsUsed >= 1 { score = Int(round(Double(baseScore) * 0.90)) }
        if hintsUsed >= 2 { score = Int(round(Double(baseScore) * 0.70)) }
        if hintsUsed >= 3 { score = Int(round(Double(baseScore) * 0.50)) }
        
        return score
    }
    
    @MainActor
    private func calculateLocalScore() -> Int {
        let language = currentCustomPhrase?.language ?? "en"
        let storedDifficulty = phraseDifficulty > 0 ? phraseDifficulty : nil
        
        let finalScore = ScoreCalculator.shared.calculateWithFallback(
            storedDifficulty: storedDifficulty,
            phrase: currentSentence,
            language: language,
            hintsUsed: hintsUsed
        )
        
        let baseDifficulty = storedDifficulty ?? ScoreCalculator.shared.calculateBaseDifficulty(phrase: currentSentence, language: language)
        print("🔍 SCORE: Using base difficulty: \(baseDifficulty) (hints: \(hintsUsed))")
        print("🔍 SCORE: Final calculated score: \(finalScore) (base: \(baseDifficulty), hints: \(hintsUsed))")
        return finalScore
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
        
        await DebugLogger.shared.sendToServer("SKIP_BUTTON_PRESSED: Starting skipCurrentGame()")
        
        // Prevent concurrent skip operations to avoid race conditions
        guard !isSkipping else {
            await DebugLogger.shared.sendToServer("SKIP_BLOCKED: Already skipping, ignoring concurrent request")
            print("⚠️ Skip already in progress, ignoring concurrent request")
            return
        }
        
        isSkipping = true
        print("🚀 Skip button pressed")
        
        // Simply move to the next phrase in the queue
        if let customPhrase = currentCustomPhrase {
            print("⏭️ Skipping phrase: \(customPhrase.content)")
            // No server calls needed - just move to next phrase in queue
            
            // Remove the skipped phrase from local queues
            let phraseIdToRemove = customPhrase.id
            let removedCounts = await MainActor.run {
                // Remove from phraseQueue
                let originalPhraseQueueCount = phraseQueue.count
                phraseQueue.removeAll { $0.id == phraseIdToRemove }
                let removedFromPhraseQueue = originalPhraseQueueCount - phraseQueue.count
                
                // Remove from lobbyDisplayQueue  
                let originalLobbyQueueCount = lobbyDisplayQueue.count
                lobbyDisplayQueue.removeAll { $0.id == phraseIdToRemove }
                let removedFromLobbyQueue = originalLobbyQueueCount - lobbyDisplayQueue.count
                
                print("📤 SKIP: Removed skipped phrase from queues - phraseQueue: \(removedFromPhraseQueue), lobbyQueue: \(removedFromLobbyQueue)")
                
                // Clear current phrase references
                currentCustomPhrase = nil
                customPhraseInfo = ""
                currentPhraseId = nil
                
                return (removedFromPhraseQueue, removedFromLobbyQueue)
            }
            
            await DebugLogger.shared.sendToServer("SKIP_QUEUE_CLEANUP: Removed phrase \(phraseIdToRemove) from local queues (phraseQueue: \(removedCounts.0), lobbyQueue: \(removedCounts.1))")
        } else {
            await DebugLogger.shared.sendToServer("SKIP_NO_CUSTOM_PHRASE: No custom phrase to skip")
        }
        
        // Start a new game regardless of skip result
        await DebugLogger.shared.sendToServer("SKIP_STARTING_NEW_GAME: About to call startNewGame")
        print("🚀 Starting new game after skip")
        await startNewGame(isUserInitiated: true)
        
        await DebugLogger.shared.sendToServer("SKIP_COMPLETED: skipCurrentGame() finished")
        
        // Reset skip flag to allow future skip operations
        isSkipping = false
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
    
    // Load total score from local storage or server
    @MainActor
    func loadTotalScore() {
        guard let playerId = playerId else {
            print("❌ LOAD_SCORE: Cannot load total score: missing playerId")
            return
        }
        
        print("💾 LOAD_SCORE_START: Loading total score for player \(playerId)")
        
        // Load from UserDefaults first (instant)
        let savedScore = UserDefaults.standard.integer(forKey: "totalScore_\(playerId)")
        print("💾 LOAD_SCORE_USERDEFAULTS: Found saved score: \(savedScore)")
        
        if savedScore > 0 {
            playerTotalScore = savedScore
            print("💾 LOAD_SCORE_SUCCESS: Loaded total score \(savedScore) from storage for player \(playerId)")
        } else {
            print("💾 LOAD_SCORE_EMPTY: No saved score found, keeping current: \(playerTotalScore)")
        }
        
        // Initialize level tracking after loading score
        initializeLevelTracking()
        
        // Then refresh from server in background (to get latest)
        Task {
            await refreshTotalScoreFromServer()
        }
    }
    
    // Refresh total score from server to ensure accuracy
    @MainActor
    func refreshTotalScoreFromServer() async {
        guard let playerId = playerId,
              let networkManager = networkManager else {
            print("❌ Cannot refresh total score: missing playerId or networkManager")
            return
        }
        
        do {
            let stats = try await networkManager.getPlayerStats(playerId: playerId)
            playerTotalScore = stats.totalScore
            print("🔄 TOTAL SCORE: Refreshed from server to \(playerTotalScore)")
            
            // Re-initialize level tracking after server refresh
            initializeLevelTracking()
        } catch {
            print("❌ Failed to refresh total score from server: \(error)")
            // Keep local score if server fails
            print("💾 PERSISTENCE: Keeping local score due to server error")
        }
    }
    
    // MARK: - Level System Methods
    
    /// Handle skill level up animation and effects
    private func handleSkillLevelUp(from oldLevelId: Int, to newLevelId: Int, newTitle: String) {
        print("🎉 SKILL LEVEL UP: Player advanced from level \(oldLevelId) to \(newLevelId) (\(newTitle))")
        
        // Trigger dramatic level-up animation sequence
        isLevelingUp = true
        
        // Optional: Spawn celebration message in game scene
        if let spawner = messageTileSpawner {
            spawner.spawnMessageTile(message: "🎉 \(newTitle.uppercased())! 🎉")
        }
        
        // Reset animation after longer dramatic duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isLevelingUp = false
        }
    }
    
    /// Initialize previousSkillLevelId when loading saved score
    private func initializeLevelTracking() {
        previousSkillLevelId = currentSkillLevel.id
        print("🎯 LEVEL: Initialized skill level tracking at level \(previousSkillLevelId) (\(currentSkillLevel.title))")
    }
    
    /// Load level configuration from server
    func loadLevelConfig() async {
        do {
            // Try to load from server first
            if let serverConfig = await fetchLevelConfigFromServer() {
                levelConfig = serverConfig 
                print("⚙️ LEVEL CONFIG: Loaded from server - \(serverConfig.skillLevels.count) skill levels")
            } else {
                // Fall back to local config file if available
                if let localConfig = loadLocalLevelConfig() {
                    levelConfig = localConfig
                    print("⚙️ LEVEL CONFIG: Loaded from local file - \(localConfig.skillLevels.count) skill levels")
                } else {
                    print("⚙️ LEVEL CONFIG: Using default - \(levelConfig.skillLevels.count) skill levels")
                }
            }
        }
    }
    
    /// Fetch level config from server endpoint
    private func fetchLevelConfigFromServer() async -> LevelConfig? {
        guard let url = URL(string: "\(AppConfig.baseURL)/api/config/levels") else { 
            print("❌ LEVEL CONFIG: Invalid server URL")
            return nil 
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ LEVEL CONFIG: Server request failed with status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let config = try JSONDecoder().decode(LevelConfig.self, from: data)
            return config
        } catch {
            print("❌ LEVEL CONFIG: Failed to fetch from server: \(error)")
            return nil
        }
    }
    
    /// Load level config from local JSON file
    private func loadLocalLevelConfig() -> LevelConfig? {
        guard let path = Bundle.main.path(forResource: "level-config", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("⚠️ LEVEL CONFIG: No local config file found")
            return nil
        }
        
        do {
            let config = try JSONDecoder().decode(LevelConfig.self, from: data)
            return config
        } catch {
            print("❌ LEVEL CONFIG: Failed to parse local config: \(error)")
            return nil
        }
    }
    
    // MARK: - Debug Methods
    
    
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
    
    // Method to refresh phrase queue for lobby display and game play
    // MARK: - Performance Monitoring
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
    }
    
    func refreshPhrasesForLobby() async {
        let networkManager = NetworkManager.shared
        
        let phrases = await networkManager.fetchPhrasesForCurrentPlayer(level: currentLevel)
        
        await MainActor.run { [self] in
            print("📥 LOBBY: BEFORE REFRESH - lobbyDisplayQueue: \(lobbyDisplayQueue.count), phraseQueue: \(phraseQueue.count)")
            
            // CRITICAL FIX: Preserve targeted phrases that were received via WebSocket push
            let existingTargetedPhrases = phraseQueue.filter { $0.targetId != nil }
            let existingTargetedLobbyPhrases = lobbyDisplayQueue.filter { $0.targetId != nil }
            
            print("📥 LOBBY: Found \(existingTargetedPhrases.count) existing targeted phrases in game queue")
            print("📥 LOBBY: Found \(existingTargetedLobbyPhrases.count) existing targeted phrases in lobby queue")
            
            // Only update if the server data is different from what we have
            let serverPhraseIds = Set(phrases.map { $0.id })
            let currentLobbyPhraseIds = Set(lobbyDisplayQueue.filter { $0.targetId == nil }.map { $0.id })
            let currentGamePhraseIds = Set(phraseQueue.filter { $0.targetId == nil }.map { $0.id })
            
            if serverPhraseIds != currentLobbyPhraseIds {
                print("📥 LOBBY: Server data changed, updating lobby display queue while preserving targeted phrases")
                lobbyDisplayQueue.removeAll()
                // Add preserved targeted phrases first (higher priority)
                lobbyDisplayQueue.append(contentsOf: existingTargetedLobbyPhrases)
                // Then add server phrases (global phrases)
                lobbyDisplayQueue.append(contentsOf: phrases)
            } else {
                print("📥 LOBBY: Server data unchanged, keeping current lobby display queue")
            }
            
            // CRITICAL FIX: Also populate phraseQueue for first game access while preserving targeted phrases
            if serverPhraseIds != currentGamePhraseIds {
                print("📥 GAME: Server data changed, updating game phrase queue while preserving targeted phrases")
                phraseQueue.removeAll()
                // Add preserved targeted phrases first (higher priority)
                phraseQueue.append(contentsOf: existingTargetedPhrases)
                // Then add server phrases (global phrases)
                phraseQueue.append(contentsOf: phrases)
            } else {
                print("📥 GAME: Server data unchanged, keeping current game phrase queue")
            }
            
            print("📥 LOBBY: AFTER REFRESH - lobbyDisplayQueue: \(lobbyDisplayQueue.count), phraseQueue: \(phraseQueue.count)")
            print("📥 LOBBY: Loaded \(phrases.count) server phrases + preserved targeted phrases")
            if !phrases.isEmpty {
                print("📥 LOBBY: Server phrase senders: \(phrases.map { $0.senderName })")
            }
            if !existingTargetedPhrases.isEmpty {
                print("📥 LOBBY: Preserved targeted phrase senders: \(existingTargetedPhrases.map { $0.senderName })")
            }
            print("📥 LOBBY: Queue status - hasWaitingPhrases: \(hasWaitingPhrases), waitingPhrasesCount: \(waitingPhrasesCount)")
        }
    }
    
    // Phrase queue management
    private func addPhraseToQueue(_ phrase: CustomPhrase) {
        phraseQueue.append(phrase)
        lobbyDisplayQueue.append(phrase) // Also add to lobby display queue
        print("📥 QUEUE: Added phrase to queue: '\(phrase.content)' from \(phrase.senderName) (Lobby: \(lobbyDisplayQueue.count))")
        
        // DEBUG: Log the targetId when adding to queue
        print("🐛 DEBUG: Adding phrase with targetId = '\(phrase.targetId ?? "nil")' from \(phrase.senderName)")
        
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
        
        // Spawn notification message tile - this should only be the "incoming" notification
        let notificationMessage = "New phrase from \(senderName) incoming!"
        messageTileSpawner?.spawnMessageTile(message: notificationMessage)
        print("📢 NOTIFICATION: Spawned notification tile for \(senderName) (phrase queued, not delivered)")
        
        // REMOVED: The delayed "Custom phrase from..." tile spawn
        // This was incorrectly showing that the phrase was being played when it was just queued
        // The "Custom phrase from..." tile should only appear when the phrase is actually delivered in checkForCustomPhrases()
    }
}