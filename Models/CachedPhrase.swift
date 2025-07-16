import Foundation

/// A phrase cached locally for offline play, extending CustomPhrase with additional metadata
struct CachedPhrase: Codable, Identifiable, Equatable, Hashable {
    
    // MARK: - Core Phrase Data
    
    /// The underlying custom phrase data
    let customPhrase: CustomPhrase
    
    /// Server-calculated difficulty score for this phrase
    let difficultyScore: Int
    
    /// When this phrase was cached locally
    let cachedAt: Date
    
    /// When this phrase was last played (nil if never played)
    var playedAt: Date?
    
    /// Number of times this phrase has been completed
    var completionCount: Int
    
    /// Best score achieved on this phrase
    var bestScore: Int?
    
    // MARK: - Computed Properties
    
    /// Unique identifier (delegates to customPhrase.id)
    var id: String {
        return customPhrase.id
    }
    
    /// Phrase content (delegates to customPhrase.content)
    var content: String {
        return customPhrase.content
    }
    
    /// Phrase language (delegates to customPhrase.language)
    var language: String {
        return customPhrase.language
    }
    
    /// Sender name (delegates to customPhrase.senderName)
    var senderName: String {
        return customPhrase.senderName
    }
    
    /// Whether this phrase has been played at least once
    var hasBeenPlayed: Bool {
        return playedAt != nil
    }
    
    /// Whether this phrase is considered "fresh" (cached recently)
    var isFresh: Bool {
        let daysSinceCached = Calendar.current.dateComponents([.day], from: cachedAt, to: Date()).day ?? 0
        return daysSinceCached <= 7 // Fresh for 7 days
    }
    
    /// Difficulty category based on score
    var difficultyCategory: String {
        switch difficultyScore {
        case 0..<50:
            return "Easy"
        case 50..<100:
            return "Medium"
        case 100..<150:
            return "Hard"
        default:
            return "Expert"
        }
    }
    
    // MARK: - Initialization
    
    /// Creates a new cached phrase from a CustomPhrase
    init(customPhrase: CustomPhrase, difficultyScore: Int, cachedAt: Date = Date()) {
        self.customPhrase = customPhrase
        self.difficultyScore = difficultyScore
        self.cachedAt = cachedAt
        self.playedAt = nil
        self.completionCount = 0
        self.bestScore = nil
    }
    
    /// Creates a cached phrase with existing play data
    init(customPhrase: CustomPhrase, difficultyScore: Int, cachedAt: Date, playedAt: Date?, completionCount: Int = 0, bestScore: Int? = nil) {
        self.customPhrase = customPhrase
        self.difficultyScore = difficultyScore
        self.cachedAt = cachedAt
        self.playedAt = playedAt
        self.completionCount = completionCount
        self.bestScore = bestScore
    }
    
    // MARK: - Mutating Methods
    
    /// Marks this phrase as played with optional score tracking
    mutating func markAsPlayed(score: Int? = nil) {
        playedAt = Date()
        completionCount += 1
        
        if let score = score {
            if bestScore == nil || score > bestScore! {
                bestScore = score
            }
        }
    }
    
    /// Resets play statistics (for testing/debugging)
    mutating func resetPlayStats() {
        playedAt = nil
        completionCount = 0
        bestScore = nil
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case customPhrase
        case difficultyScore
        case cachedAt
        case playedAt
        case completionCount
        case bestScore
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        customPhrase = try container.decode(CustomPhrase.self, forKey: .customPhrase)
        difficultyScore = try container.decode(Int.self, forKey: .difficultyScore)
        cachedAt = try container.decode(Date.self, forKey: .cachedAt)
        playedAt = try container.decodeIfPresent(Date.self, forKey: .playedAt)
        completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(customPhrase, forKey: .customPhrase)
        try container.encode(difficultyScore, forKey: .difficultyScore)
        try container.encode(cachedAt, forKey: .cachedAt)
        try container.encodeIfPresent(playedAt, forKey: .playedAt)
        try container.encode(completionCount, forKey: .completionCount)
        try container.encodeIfPresent(bestScore, forKey: .bestScore)
    }
    
    // MARK: - Equatable Implementation
    
    static func == (lhs: CachedPhrase, rhs: CachedPhrase) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Hashable Implementation
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Array Extensions

extension Array where Element == CachedPhrase {
    
    /// Filters phrases that haven't been played
    var unplayed: [CachedPhrase] {
        return filter { !$0.hasBeenPlayed }
    }
    
    /// Filters phrases that have been played
    var played: [CachedPhrase] {
        return filter { $0.hasBeenPlayed }
    }
    
    /// Filters phrases within a difficulty range
    func withDifficulty(in range: DifficultyRange) -> [CachedPhrase] {
        return filter { range.contains($0.difficultyScore) }
    }
    
    /// Filters phrases by difficulty category
    func withDifficultyCategory(_ category: String) -> [CachedPhrase] {
        return filter { $0.difficultyCategory == category }
    }
    
    /// Sorts phrases by difficulty score (ascending)
    var sortedByDifficulty: [CachedPhrase] {
        return sorted { $0.difficultyScore < $1.difficultyScore }
    }
    
    /// Sorts phrases by cached date (newest first)
    var sortedByDate: [CachedPhrase] {
        return sorted { $0.cachedAt > $1.cachedAt }
    }
    
    /// Gets a random unplayed phrase, or nil if none available
    func randomUnplayed() -> CachedPhrase? {
        return unplayed.randomElement()
    }
    
    /// Gets phrases appropriate for the current player level
    func forCurrentPlayerLevel() -> [CachedPhrase] {
        let range = PlayerProgressionManager.getCurrentDifficultyRange()
        return withDifficulty(in: range)
    }
    
    /// Gets count of unplayed phrases for current level
    var unplayedCountForCurrentLevel: Int {
        return forCurrentPlayerLevel().unplayed.count
    }
}

// MARK: - Statistics

extension Array where Element == CachedPhrase {
    
    /// Cache statistics for monitoring and debugging
    var cacheStats: CacheStatistics {
        return CacheStatistics(
            totalPhrases: count,
            playedPhrases: played.count,
            unplayedPhrases: unplayed.count,
            averageDifficulty: isEmpty ? 0 : map(\.difficultyScore).reduce(0, +) / count,
            difficultyDistribution: Dictionary(grouping: self) { $0.difficultyCategory }
                .mapValues { $0.count }
        )
    }
}

/// Statistics about cached phrases
struct CacheStatistics: Codable {
    let totalPhrases: Int
    let playedPhrases: Int
    let unplayedPhrases: Int
    let averageDifficulty: Int
    let difficultyDistribution: [String: Int]
    
    var playedPercentage: Double {
        guard totalPhrases > 0 else { return 0 }
        return Double(playedPhrases) / Double(totalPhrases) * 100
    }
}