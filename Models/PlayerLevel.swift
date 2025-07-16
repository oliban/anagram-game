import Foundation

/// Represents a difficulty range for phrase filtering
struct DifficultyRange: Codable, Equatable {
    let min: Int
    let max: Int
    
    /// Creates a difficulty range with validation
    init(min: Int, max: Int) {
        self.min = Swift.min(min, max) // Ensure min <= max
        self.max = Swift.max(min, max)
    }
    
    /// Checks if a difficulty score falls within this range
    func contains(_ difficulty: Int) -> Bool {
        return difficulty >= min && difficulty <= max
    }
    
    /// Returns a human-readable description of the range
    var description: String {
        return "\(min)-\(max)"
    }
}

/// Represents a player's progression level with associated difficulty range
struct PlayerLevel: Codable, Equatable {
    let level: Int
    let difficultyRange: DifficultyRange
    let title: String
    let requiredXP: Int // XP needed to reach this level
    
    init(level: Int, minDifficulty: Int, maxDifficulty: Int, title: String, requiredXP: Int = 0) {
        self.level = level
        self.difficultyRange = DifficultyRange(min: minDifficulty, max: maxDifficulty)
        self.title = title
        self.requiredXP = requiredXP
    }
}

/// Manages player progression and level-based difficulty filtering
class PlayerProgressionManager {
    
    // MARK: - Level Definitions
    
    /// All available player levels with their difficulty ranges
    static let allLevels: [PlayerLevel] = [
        PlayerLevel(level: 1, minDifficulty: 0, maxDifficulty: 50, title: "Novice", requiredXP: 0),
        PlayerLevel(level: 2, minDifficulty: 25, maxDifficulty: 75, title: "Apprentice", requiredXP: 100),
        PlayerLevel(level: 3, minDifficulty: 50, maxDifficulty: 100, title: "Skilled", requiredXP: 250),
        PlayerLevel(level: 4, minDifficulty: 75, maxDifficulty: 125, title: "Expert", requiredXP: 500),
        PlayerLevel(level: 5, minDifficulty: 100, maxDifficulty: 150, title: "Master", requiredXP: 1000),
        PlayerLevel(level: 6, minDifficulty: 125, maxDifficulty: 200, title: "Grandmaster", requiredXP: 2000)
    ]
    
    // MARK: - Current Level Management
    
    /// Returns the current player level (defaults to level 1 for now)
    /// TODO: Replace with actual progression tracking when implemented
    static func getCurrentPlayerLevel() -> PlayerLevel {
        return allLevels[0] // Always return level 1 for now
    }
    
    /// Gets the difficulty range for the current player level
    static func getCurrentDifficultyRange() -> DifficultyRange {
        return getCurrentPlayerLevel().difficultyRange
    }
    
    /// Gets the difficulty range for a specific level
    static func getDifficultyRange(for level: Int) -> DifficultyRange? {
        return allLevels.first { $0.level == level }?.difficultyRange
    }
    
    // MARK: - Level Progression (Future Implementation)
    
    /// Calculates what level a player should be based on XP
    /// TODO: Implement when progression system is added
    static func calculateLevel(for xp: Int) -> PlayerLevel {
        // Find the highest level the player has enough XP for
        let achievedLevel = allLevels.reversed().first { level in
            xp >= level.requiredXP
        } ?? allLevels[0]
        
        return achievedLevel
    }
    
    /// Gets the next level for progression display
    static func getNextLevel(from currentLevel: PlayerLevel) -> PlayerLevel? {
        let currentIndex = allLevels.firstIndex { $0.level == currentLevel.level } ?? 0
        let nextIndex = currentIndex + 1
        
        return nextIndex < allLevels.count ? allLevels[nextIndex] : nil
    }
    
    /// Calculates XP needed to reach the next level
    static func xpToNextLevel(currentXP: Int, currentLevel: PlayerLevel) -> Int {
        guard let nextLevel = getNextLevel(from: currentLevel) else {
            return 0 // Already at max level
        }
        
        return max(0, nextLevel.requiredXP - currentXP)
    }
    
    // MARK: - Phrase Filtering
    
    /// Filters phrases by current player's difficulty range
    static func filterPhrasesForCurrentLevel<T>(_ phrases: [T], getDifficulty: (T) -> Int) -> [T] {
        let range = getCurrentDifficultyRange()
        return phrases.filter { phrase in
            range.contains(getDifficulty(phrase))
        }
    }
    
    /// Checks if a phrase is appropriate for the current player level
    static func isPhraseAppropriate(difficulty: Int) -> Bool {
        return getCurrentDifficultyRange().contains(difficulty)
    }
    
    // MARK: - Debug and Testing
    
    /// Forces a specific level for testing purposes
    /// TODO: Remove when actual progression is implemented
    private static var debugLevel: PlayerLevel?
    
    static func setDebugLevel(_ level: Int) {
        debugLevel = allLevels.first { $0.level == level }
    }
    
    static func clearDebugLevel() {
        debugLevel = nil
    }
    
    /// Returns debug level if set, otherwise current level
    static func getEffectivePlayerLevel() -> PlayerLevel {
        return debugLevel ?? getCurrentPlayerLevel()
    }
}