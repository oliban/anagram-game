import Foundation
import SwiftData

@Observable
class GameModel {
    var currentSentence: String = "" {
        didSet {
            print("🎮 GAME: currentSentence changed from '\(oldValue)' to '\(currentSentence)'")
        }
    }
    var scrambledLetters: [String] = []
    var gameState: GameState = .playing
    var wordsCompleted: Int = 0
    var customPhraseInfo: String = "" {
        didSet {
            print("🎮 GAME: customPhraseInfo changed from '\(oldValue)' to '\(customPhraseInfo)'")
        }
    }
    
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
    
    func startNewGame() async {
        print("🎮 GAME: startNewGame() called from:")
        print("🎮 GAME: Call stack: \(Thread.callStackSymbols.prefix(5))")
        
        // Prevent multiple concurrent calls
        guard !isStartingNewGame else {
            print("🎮 GAME: Already starting new game, ignoring duplicate call")
            return
        }
        
        isStartingNewGame = true
        
        // First check for custom phrases
        await checkForCustomPhrases()
        
        // Reset flag on main thread
        await MainActor.run {
            self.isStartingNewGame = false
        }
    }
    
    @MainActor
    private func checkForCustomPhrases() async {
        gameState = .loading
        
        // Check if there are any pending custom phrases (use local cache first, then API)
        let networkManager = NetworkManager.shared
        var customPhrases = networkManager.pendingPhrases
        
        print("🎮 GAME: Found \(customPhrases.count) pending phrases in local cache")
        
        // If no local phrases, fetch from server as fallback
        if customPhrases.isEmpty {
            customPhrases = await networkManager.fetchPhrasesForCurrentPlayer()
            print("🎮 GAME: Fetched \(customPhrases.count) custom phrases from server")
        }
        
        for (index, phrase) in customPhrases.enumerated() {
            print("🎮 GAME: Phrase \(index): '\(phrase.content)' from \(phrase.senderName) (ID: \(phrase.id))")
        }
        
        if let firstPhrase = customPhrases.first {
            print("🎯 GAME PREVIEW: About to use custom phrase: '\(firstPhrase.content)' from \(firstPhrase.senderName)")
            print("🎯 GAME PREVIEW: This will be your new puzzle!")
            
            // Use the first custom phrase
            currentCustomPhrase = firstPhrase
            currentSentence = firstPhrase.content
            customPhraseInfo = "Custom phrase from \(firstPhrase.senderName)"
            
            print("🎮 GAME: Using custom phrase: '\(firstPhrase.content)' from \(firstPhrase.senderName) (ID: \(firstPhrase.id))")
            
            // TEMPORARILY DISABLED: Remove from local cache immediately
            // if let index = networkManager.pendingPhrases.firstIndex(where: { $0.id == firstPhrase.id }) {
            //     networkManager.pendingPhrases.remove(at: index)
            //     networkManager.debugCounter += 100 // Add 100 to show removal
            //     print("🎮 GAME: Removed phrase from local cache - debugCounter now: \(networkManager.debugCounter)")
            // }
            print("🎮 GAME: SKIPPED removing phrase from cache for testing")
            
            // Mark the phrase as consumed on server
            let consumeSuccess = await networkManager.consumePhrase(phraseId: firstPhrase.id)
            print("🎮 GAME: Phrase consumption result: \(consumeSuccess)")
        } else {
            // Use a random sentence from the default collection
            print("🎮 GAME: No custom phrases found, using default sentence")
            guard !sentences.isEmpty else {
                gameState = .error
                return
            }
            currentCustomPhrase = nil
            let selectedSentence = sentences.randomElement() ?? ""
            print("🎯 GAME PREVIEW: About to use default sentence: '\(selectedSentence)'")
            print("🎯 GAME PREVIEW: This will be your new puzzle!")
            currentSentence = selectedSentence
            customPhraseInfo = ""
            print("🎮 GAME: Selected default sentence: '\(selectedSentence)'")
        }
        
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
    }
    
    private func scrambleLetters() {
        let letters = currentSentence.replacingOccurrences(of: " ", with: "")
        scrambledLetters = Array(letters).map { String($0) }.shuffled()
    }
    
    func resetGame() {
        scrambleLetters()
        gameState = .playing
        wordsCompleted = 0
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
    }
}