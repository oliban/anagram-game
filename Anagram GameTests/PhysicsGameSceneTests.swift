import XCTest
import SpriteKit
import CoreMotion
@testable import Anagram_Game

final class PhysicsGameSceneTests: XCTestCase {
    var gameModel: GameModel!
    var scene: PhysicsGameScene!
    var testSize: CGSize!
    
    override func setUpWithError() throws {
        gameModel = GameModel()
        testSize = CGSize(width: 400, height: 800)
        scene = PhysicsGameScene(gameModel: gameModel, size: testSize)
    }
    
    override func tearDownWithError() throws {
        scene = nil
        gameModel = nil
    }
    
    // MARK: - Gravity Tests
    
    func testGravityThresholdNormalMode() throws {
        let normalGravity = CMAcceleration(x: 0.1, y: -0.5, z: -1.0)
        
        scene.updateGravity(from: normalGravity)
        
        // Should not trigger falling mode
        XCTAssertFalse(scene.debugText.contains("FALLING"))
        XCTAssertTrue(scene.debugText.contains("x=-0.10"))
        XCTAssertTrue(scene.debugText.contains("y=-0.50"))
    }
    
    func testGravityThresholdFallingMode() throws {
        let fallingGravity = CMAcceleration(x: 0.2, y: -0.95, z: -1.0)
        
        scene.updateGravity(from: fallingGravity)
        
        // Should trigger falling mode
        XCTAssertTrue(scene.debugText.contains("FALLING"))
        XCTAssertTrue(scene.debugText.contains("x=-0.20"))
        XCTAssertTrue(scene.debugText.contains("y=-0.95"))
    }
    
    func testGravityThresholdExactBoundary() throws {
        let boundaryGravity = CMAcceleration(x: 0.0, y: -0.94, z: -1.0)
        
        scene.updateGravity(from: boundaryGravity)
        
        // Should NOT trigger falling mode (>= -0.94)
        XCTAssertFalse(scene.debugText.contains("FALLING"))
    }
    
    func testGravityPhysicsApplication() throws {
        let testGravity = CMAcceleration(x: 0.1, y: -0.2, z: -1.0)
        
        scene.updateGravity(from: testGravity)
        
        let appliedGravity = scene.physicsWorld.gravity
        // Normal mode: x = 0.1 * 50 = 5.0, y = -(-0.2) * 50 - 9.8 = 0.2
        XCTAssertEqual(appliedGravity.dx, 5.0, accuracy: 0.1)
        XCTAssertEqual(appliedGravity.dy, 0.2, accuracy: 0.1)
    }
    
    func testGravityPhysicsFallingMode() throws {
        let fallingGravity = CMAcceleration(x: 0.2, y: -0.95, z: -1.0)
        
        scene.updateGravity(from: fallingGravity)
        
        let appliedGravity = scene.physicsWorld.gravity
        // Falling mode: x = 0.2 * 300 = 60.0, y = 500.0
        XCTAssertEqual(appliedGravity.dx, 60.0, accuracy: 0.1)
        XCTAssertEqual(appliedGravity.dy, 500.0, accuracy: 0.1)
    }
}

// MARK: - Mock Tile Tests for Scoring

final class MockTileGroupingTests: XCTestCase {
    
    func testTileGroupingBasicWord() throws {
        // Simulate tiles positioned to form "CAT"
        let mockTiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "T", position: CGPoint(x: 160, y: 200))
        ]
        
        let groups = groupTilesByProximity(tiles: mockTiles, radius: 45)
        
        XCTAssertEqual(groups.count, 1, "Should form one group")
        XCTAssertEqual(groups[0].count, 3, "Group should have 3 tiles")
        
        let formedWord = groups[0].map { $0.letter }.joined()
        XCTAssertEqual(formedWord, "CAT")
    }
    
    func testTileGroupingSeparateWords() throws {
        // Simulate tiles positioned to form "CAT" and "DOG" separately
        let mockTiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "T", position: CGPoint(x: 160, y: 200)),
            // Separate group for "DOG"
            MockLetterTile(letter: "D", position: CGPoint(x: 300, y: 200)),
            MockLetterTile(letter: "O", position: CGPoint(x: 330, y: 200)),
            MockLetterTile(letter: "G", position: CGPoint(x: 360, y: 200))
        ]
        
        let groups = groupTilesByProximity(tiles: mockTiles, radius: 45)
        
        XCTAssertEqual(groups.count, 2, "Should form two groups")
        
        let words = groups.map { group in
            group.map { $0.letter }.joined()
        }.sorted()
        
        XCTAssertEqual(words, ["CAT", "DOG"])
    }
    
    func testTileGroupingTooFarApart() throws {
        // Simulate tiles too far apart to group
        let mockTiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 200, y: 200)), // 100 pixels apart > 45 radius
            MockLetterTile(letter: "T", position: CGPoint(x: 300, y: 200))
        ]
        
        let groups = groupTilesByProximity(tiles: mockTiles, radius: 45)
        
        XCTAssertEqual(groups.count, 3, "Should form three separate groups")
        groups.forEach { group in
            XCTAssertEqual(group.count, 1, "Each group should have only one tile")
        }
    }
    
    func testWordValidationCorrectWords() throws {
        let targetWords = ["Hello", "world"]
        let foundWords = ["Hello", "world"]
        
        let isComplete = validateWordsMatch(target: targetWords, found: foundWords)
        XCTAssertTrue(isComplete)
    }
    
    func testWordValidationIncompleteWords() throws {
        let targetWords = ["Hello", "world"]
        let foundWords = ["Hello"]
        
        let isComplete = validateWordsMatch(target: targetWords, found: foundWords)
        XCTAssertFalse(isComplete)
    }
    
    func testWordValidationWrongWords() throws {
        let targetWords = ["Hello", "world"]
        let foundWords = ["Hello", "earth"]
        
        let isComplete = validateWordsMatch(target: targetWords, found: foundWords)
        XCTAssertFalse(isComplete)
    }
    
    func testWordValidationCaseInsensitive() throws {
        let targetWords = ["Hello", "World"]
        let foundWords = ["HELLO", "world"]
        
        let isComplete = validateWordsMatch(target: targetWords, found: foundWords)
        XCTAssertTrue(isComplete)
    }
    
    func testWordValidationExtraWords() throws {
        let targetWords = ["Hello", "world"]
        let foundWords = ["Hello", "world", "extra"]
        
        let isComplete = validateWordsMatch(target: targetWords, found: foundWords)
        XCTAssertFalse(isComplete)
    }
}

// MARK: - Mock Classes and Helper Functions

class MockLetterTile {
    let letter: String
    let position: CGPoint
    
    init(letter: String, position: CGPoint) {
        self.letter = letter
        self.position = position
    }
}

func groupTilesByProximity(tiles: [MockLetterTile], radius: CGFloat) -> [[MockLetterTile]] {
    var groups: [[MockLetterTile]] = []
    var processedTiles = Set<ObjectIdentifier>()
    
    for tile in tiles {
        let tileId = ObjectIdentifier(tile)
        if processedTiles.contains(tileId) { continue }
        
        var currentGroup: [MockLetterTile] = []
        var queue: [MockLetterTile] = [tile]
        
        while !queue.isEmpty {
            let currentTile = queue.removeFirst()
            let currentId = ObjectIdentifier(currentTile)
            if processedTiles.contains(currentId) { continue }
            
            currentGroup.append(currentTile)
            processedTiles.insert(currentId)
            
            for otherTile in tiles {
                let otherId = ObjectIdentifier(otherTile)
                if processedTiles.contains(otherId) { continue }
                
                let distance = sqrt(pow(currentTile.position.x - otherTile.position.x, 2) + 
                                  pow(currentTile.position.y - otherTile.position.y, 2))
                if distance <= radius {
                    queue.append(otherTile)
                }
            }
        }
        
        if !currentGroup.isEmpty {
            currentGroup.sort { $0.position.x < $1.position.x }
            groups.append(currentGroup)
        }
    }
    
    return groups
}

func validateWordsMatch(target: [String], found: [String]) -> Bool {
    guard target.count == found.count else { return false }
    
    let normalizedTarget = Set(target.map { $0.uppercased() })
    let normalizedFound = Set(found.map { $0.uppercased() })
    
    return normalizedTarget == normalizedFound
}

// MARK: - Tile Selection Algorithm Tests

final class TileSelectionTests: XCTestCase {
    
    func testSimpleWordFormation() throws {
        // Test "CAT" with tiles in correct order
        let tiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "T", position: CGPoint(x: 160, y: 200))
        ]
        
        let result = findBestTileCombination(for: ["C", "A", "T"], from: tiles, excluding: Set())
        
        XCTAssertNotNil(result, "Should find valid combination for CAT")
        if let result = result {
            let formedWord = result.map { $0.letter }.joined()
            XCTAssertEqual(formedWord, "CAT")
        }
    }
    
    func testWordFormationWithDuplicateLetters() throws {
        // Test "LOVE" with two O tiles at different positions
        let tiles = [
            MockLetterTile(letter: "L", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "O", position: CGPoint(x: 130, y: 200)), // First O
            MockLetterTile(letter: "V", position: CGPoint(x: 160, y: 200)),
            MockLetterTile(letter: "E", position: CGPoint(x: 190, y: 200)),
            MockLetterTile(letter: "O", position: CGPoint(x: 220, y: 200))  // Second O
        ]
        
        let result = findBestTileCombination(for: ["L", "O", "V", "E"], from: tiles, excluding: Set())
        
        XCTAssertNotNil(result, "Should find valid combination for LOVE")
        if let result = result {
            let sortedTiles = result.sorted { $0.position.x < $1.position.x }
            let formedWord = sortedTiles.map { $0.letter }.joined()
            XCTAssertEqual(formedWord, "LOVE")
            // Should use the first O (at x=130), not the second O (at x=220)
            XCTAssertEqual(sortedTiles[1].position.x, 130)
        }
    }
    
    func testIncorrectSpatialOrder() throws {
        // Test tiles that spell "EVOL" when sorted by position (should NOT match "LOVE")
        let tiles = [
            MockLetterTile(letter: "E", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "V", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "O", position: CGPoint(x: 160, y: 200)),
            MockLetterTile(letter: "L", position: CGPoint(x: 190, y: 200))
        ]
        
        let result = findBestTileCombination(for: ["L", "O", "V", "E"], from: tiles, excluding: Set())
        
        XCTAssertNil(result, "Should NOT find valid combination when spatial order is wrong")
    }
    
    func testMultipleDuplicatesComplex() throws {
        // Test "TWO PARTIES" scenario with multiple T's and other duplicates
        let tiles = [
            MockLetterTile(letter: "T", position: CGPoint(x: 100, y: 200)), // First T (for TWO)
            MockLetterTile(letter: "W", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "O", position: CGPoint(x: 160, y: 200)),
            MockLetterTile(letter: "P", position: CGPoint(x: 200, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 230, y: 200)),
            MockLetterTile(letter: "R", position: CGPoint(x: 260, y: 200)),
            MockLetterTile(letter: "T", position: CGPoint(x: 290, y: 200)), // Second T (for PARTIES)
            MockLetterTile(letter: "I", position: CGPoint(x: 320, y: 200)),
            MockLetterTile(letter: "E", position: CGPoint(x: 350, y: 200)),
            MockLetterTile(letter: "S", position: CGPoint(x: 380, y: 200))
        ]
        
        // Test finding "TWO"
        let twoResult = findBestTileCombination(for: ["T", "W", "O"], from: tiles, excluding: Set())
        XCTAssertNotNil(twoResult, "Should find valid combination for TWO")
        if let twoResult = twoResult {
            let sortedTiles = twoResult.sorted { $0.position.x < $1.position.x }
            let formedWord = sortedTiles.map { $0.letter }.joined()
            XCTAssertEqual(formedWord, "TWO")
            // Should use the first T (at x=100)
            XCTAssertEqual(sortedTiles[0].position.x, 100)
        }
        
        // Test finding "PARTIES" excluding tiles used for "TWO"
        let usedTiles = Set(twoResult!)
        let partiesResult = findBestTileCombination(for: ["P", "A", "R", "T", "I", "E", "S"], from: tiles, excluding: usedTiles)
        XCTAssertNotNil(partiesResult, "Should find valid combination for PARTIES")
        if let partiesResult = partiesResult {
            let sortedTiles = partiesResult.sorted { $0.position.x < $1.position.x }
            let formedWord = sortedTiles.map { $0.letter }.joined()
            XCTAssertEqual(formedWord, "PARTIES")
            // Should use the second T (at x=290)
            let tTile = sortedTiles.first { $0.letter == "T" }
            XCTAssertEqual(tTile?.position.x, 290)
        }
    }
    
    func testInsufficientTiles() throws {
        // Test when there aren't enough tiles
        let tiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200))
            // Missing T for "CAT"
        ]
        
        let result = findBestTileCombination(for: ["C", "A", "T"], from: tiles, excluding: Set())
        
        XCTAssertNil(result, "Should return nil when insufficient tiles")
    }
    
    func testExcludedTiles() throws {
        // Test that excluded tiles are properly ignored
        let tiles = [
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)),
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200)),
            MockLetterTile(letter: "T", position: CGPoint(x: 160, y: 200))
        ]
        
        let excludedTiles = Set([tiles[0]]) // Exclude the "C" tile
        let result = findBestTileCombination(for: ["C", "A", "T"], from: tiles, excluding: excludedTiles)
        
        XCTAssertNil(result, "Should return nil when required tile is excluded")
    }
    
    func testScrambledOrder() throws {
        // Test with tiles in scrambled positions that can form the word
        let tiles = [
            MockLetterTile(letter: "T", position: CGPoint(x: 160, y: 200)), // T at rightmost position
            MockLetterTile(letter: "C", position: CGPoint(x: 100, y: 200)), // C at leftmost position  
            MockLetterTile(letter: "A", position: CGPoint(x: 130, y: 200))  // A in middle
        ]
        
        let result = findBestTileCombination(for: ["C", "A", "T"], from: tiles, excluding: Set())
        
        XCTAssertNotNil(result, "Should find valid combination for CAT even when tiles are scrambled")
        if let result = result {
            let sortedTiles = result.sorted { $0.position.x < $1.position.x }
            let formedWord = sortedTiles.map { $0.letter }.joined()
            XCTAssertEqual(formedWord, "CAT")
        }
    }
}

// MARK: - Mock Classes Extended for Tile Selection

extension MockLetterTile: Hashable {
    static func == (lhs: MockLetterTile, rhs: MockLetterTile) -> Bool {
        return lhs.letter == rhs.letter && lhs.position == rhs.position
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(letter)
        hasher.combine(position.x)
        hasher.combine(position.y)
    }
}

// MARK: - Helper function to test the algorithm

func findBestTileCombination(for targetLetters: [Character], from allTiles: [MockLetterTile], excluding usedTiles: Set<MockLetterTile>) -> [MockLetterTile]? {
    // Filter out already used tiles
    let availableTiles = allTiles.filter { !usedTiles.contains($0) }
    
    // Count how many of each letter we need
    var letterCounts: [Character: Int] = [:]
    for letter in targetLetters {
        let upperLetter = Character(String(letter).uppercased())
        letterCounts[upperLetter, default: 0] += 1
    }
    
    // Get all tiles grouped by letter type
    var tilesByLetter: [Character: [MockLetterTile]] = [:]
    for tile in availableTiles {
        let letter = Character(tile.letter.uppercased())
        tilesByLetter[letter, default: []].append(tile)
    }
    
    // Check if we have enough tiles for each required letter
    for (letter, requiredCount) in letterCounts {
        let availableCount = tilesByLetter[letter]?.count ?? 0
        if availableCount < requiredCount {
            return nil
        }
    }
    
    // Try all possible combinations of tiles and find one that spells the word correctly when sorted by position
    let targetWord = String(targetLetters).uppercased()
    let allCombinations = generateTileCombinations(for: targetLetters, from: tilesByLetter)
    
    // Find the combination that spells the word correctly when arranged left-to-right
    for combination in allCombinations {
        let sortedTiles = combination.sorted { $0.position.x < $1.position.x }
        let formedWord = sortedTiles.map { $0.letter }.joined().uppercased()
        
        if formedWord == targetWord {
            return sortedTiles
        }
    }
    
    return nil
}

func generateTileCombinations(for targetLetters: [Character], from tilesByLetter: [Character: [MockLetterTile]]) -> [[MockLetterTile]] {
    // Create a recursive function to generate all possible combinations
    func generateCombinations(remainingLetters: [Character], currentCombination: [MockLetterTile], usedTiles: Set<MockLetterTile>) -> [[MockLetterTile]] {
        // Base case: no more letters to assign
        if remainingLetters.isEmpty {
            return [currentCombination]
        }
        
        let nextLetter = remainingLetters[0]
        let remainingAfterNext = Array(remainingLetters.dropFirst())
        
        // Get all available tiles for this letter
        let candidateTiles = tilesByLetter[nextLetter] ?? []
        let availableTiles = candidateTiles.filter { !usedTiles.contains($0) }
        
        var results: [[MockLetterTile]] = []
        
        // Try each available tile for this letter position
        for tile in availableTiles {
            var newCombination = currentCombination
            newCombination.append(tile)
            
            var newUsedTiles = usedTiles
            newUsedTiles.insert(tile)
            
            // Recursively generate combinations for remaining letters
            let subCombinations = generateCombinations(
                remainingLetters: remainingAfterNext,
                currentCombination: newCombination,
                usedTiles: newUsedTiles
            )
            
            results.append(contentsOf: subCombinations)
        }
        
        return results
    }
    
    return generateCombinations(remainingLetters: targetLetters, currentCombination: [], usedTiles: Set())
}

// MARK: - Performance Tests

final class ScoringPerformanceTests: XCTestCase {
    
    func testScoringPerformanceWithManyTiles() throws {
        // Test performance with 50 tiles
        let tiles = (0..<50).map { i in
            MockLetterTile(
                letter: String(Character(UnicodeScalar(65 + (i % 26))!)), // A-Z
                position: CGPoint(x: CGFloat(i * 10), y: CGFloat((i / 10) * 50))
            )
        }
        
        measure {
            _ = groupTilesByProximity(tiles: tiles, radius: 45)
        }
    }
    
    func testWordValidationPerformance() throws {
        let targetWords = Array(0..<100).map { "Word\($0)" }
        let foundWords = Array(0..<100).map { "Word\($0)" }
        
        measure {
            _ = validateWordsMatch(target: targetWords, found: foundWords)
        }
    }
}