import Foundation
import SwiftData

@Observable
class GameModel {
    var currentSentence: String = ""
    var scrambledLetters: [String] = []
    var gameState: GameState = .playing
    var wordsCompleted: Int = 0
    
    private var sentences: [String] = []
    
    enum GameState {
        case playing
        case completed
        case loading
        case error
    }
    
    init() {
        loadSentences()
        startNewGame()
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
    
    func startNewGame() {
        guard !sentences.isEmpty else {
            gameState = .error
            return
        }
        
        currentSentence = sentences.randomElement() ?? ""
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