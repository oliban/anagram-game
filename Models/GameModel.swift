import Foundation
import SwiftData

@Observable
class GameModel {
    var currentSentence: String = ""
    var scrambledLetters: [String] = []
    var gameState: GameState = .playing
    var wordsCompleted: Int = 0
    var customPhraseInfo: String = ""
    
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
        
        // Prevent multiple concurrent calls
        guard !isStartingNewGame else {
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
        
        
        // If no local phrases, fetch from server as fallback
        if customPhrases.isEmpty {
            customPhrases = await networkManager.fetchPhrasesForCurrentPlayer()
        }
        
        
        if let firstPhrase = customPhrases.first {
            
            // Use the first custom phrase
            currentCustomPhrase = firstPhrase
            currentSentence = firstPhrase.content
            customPhraseInfo = "Custom phrase from \(firstPhrase.senderName)"
            
            
            // TEMPORARILY DISABLED: Remove from local cache immediately
            // if let index = networkManager.pendingPhrases.firstIndex(where: { $0.id == firstPhrase.id }) {
            //     networkManager.pendingPhrases.remove(at: index)
            // }
            
            // Mark the phrase as consumed on server
            let consumeSuccess = await networkManager.consumePhrase(phraseId: firstPhrase.id)
        } else {
            // Use a random sentence from the default collection
            guard !sentences.isEmpty else {
                gameState = .error
                return
            }
            currentCustomPhrase = nil
            let selectedSentence = sentences.randomElement() ?? ""
            currentSentence = selectedSentence
            customPhraseInfo = ""
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