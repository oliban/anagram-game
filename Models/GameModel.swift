import Foundation
import SwiftData

@Observable
class GameModel {
    var currentSentence: String = ""
    var scrambledLetters: [String] = []
    var gameState: GameState = .playing
    var wordsCompleted: Int = 0
    var customPhraseInfo: String = ""
    
    // Hint system state
    var currentPhraseId: String? = nil
    var currentHints: [String] = []
    var currentScore: Int = 0
    var hintsUsed: Int = 0
    
    private var sentences: [String] = []
    private var currentCustomPhrase: CustomPhrase? = nil
    private var isStartingNewGame = false
    
    enum GameState {
        case playing
        case completed
        case loading
        case error
    }
    
    init() {
        loadSentences()
        Task {
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
        
        // PRIORITY 1: Check for push-delivered phrase (instant delivery) - ONLY for user-initiated actions
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
            // FALLBACK: Fetch from server if no push-delivered phrase
            print("🔍 GAME: No push-delivered phrase, fetching from server")
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
        
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
        
        // Reset hint state for new game
        currentHints = []
        currentScore = 0
        hintsUsed = 0
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
        hintsUsed = 0
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
    
    func completeGame() {
        gameState = .completed
        
        // Complete phrase on server if we have a phrase ID
        if let phraseId = currentPhraseId {
            Task {
                let networkManager = NetworkManager.shared
                let _ = await networkManager.completePhrase(phraseId: phraseId)
            }
        }
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
        }
        
        // Start a new game regardless of skip result
        print("🚀 Starting new game after skip")
        await startNewGame(isUserInitiated: true)
    }
    
    func addHint(_ hint: String) {
        currentHints.append(hint)
        hintsUsed += 1
    }
}