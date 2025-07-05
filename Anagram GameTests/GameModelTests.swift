import XCTest
@testable import Anagram_Game

final class GameModelTests: XCTestCase {
    var gameModel: GameModel!
    
    override func setUpWithError() throws {
        gameModel = GameModel()
    }
    
    override func tearDownWithError() throws {
        gameModel = nil
    }
    
    func testGameModelInitialization() throws {
        XCTAssertNotNil(gameModel.currentSentence)
        XCTAssertFalse(gameModel.scrambledLetters.isEmpty)
        XCTAssertEqual(gameModel.gameState, .playing)
        XCTAssertEqual(gameModel.wordsCompleted, 0)
    }
    
    func testScrambledLettersContainAllCharacters() throws {
        let originalLetters = gameModel.currentSentence.replacingOccurrences(of: " ", with: "")
        let scrambledString = gameModel.scrambledLetters.joined()
        
        XCTAssertEqual(originalLetters.count, scrambledString.count)
        
        for char in originalLetters {
            XCTAssertTrue(scrambledString.contains(char))
        }
    }
    
    func testResetGame() throws {
        let originalScrambledLetters = gameModel.scrambledLetters
        gameModel.wordsCompleted = 5
        
        gameModel.resetGame()
        
        XCTAssertEqual(gameModel.gameState, .playing)
        XCTAssertEqual(gameModel.wordsCompleted, 0)
        XCTAssertNotEqual(originalScrambledLetters, gameModel.scrambledLetters)
    }
    
    func testValidateWordCompletion() throws {
        gameModel.currentSentence = "The quick brown fox"
        let correctWords = ["The", "quick", "brown", "fox"]
        let incorrectWords = ["The", "quick", "brown"]
        let wrongWords = ["The", "quick", "brown", "cat"]
        
        XCTAssertTrue(gameModel.validateWordCompletion(formedWords: correctWords))
        XCTAssertFalse(gameModel.validateWordCompletion(formedWords: incorrectWords))
        XCTAssertFalse(gameModel.validateWordCompletion(formedWords: wrongWords))
    }
    
    func testCompleteGame() throws {
        gameModel.completeGame()
        XCTAssertEqual(gameModel.gameState, .completed)
    }
    
    func testStartNewGame() throws {
        gameModel.gameState = .completed
        gameModel.wordsCompleted = 10
        
        gameModel.startNewGame()
        
        XCTAssertEqual(gameModel.gameState, .playing)
        XCTAssertEqual(gameModel.wordsCompleted, 0)
        XCTAssertFalse(gameModel.currentSentence.isEmpty)
        XCTAssertFalse(gameModel.scrambledLetters.isEmpty)
    }
}