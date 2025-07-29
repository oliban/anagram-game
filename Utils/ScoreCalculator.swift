//
//  ScoreCalculator.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//

import Foundation

/// Centralized score calculation utility that handles all scoring logic
/// Eliminates duplicate code across GameModel, PhysicsGameView, and NetworkManager
class ScoreCalculator {
    
    // MARK: - Shared Instance
    static let shared = ScoreCalculator()
    private init() {}
    
    // MARK: - Base Difficulty Calculation
    
    /// Calculates the base difficulty score for a phrase using the shared algorithm
    /// - Parameters:
    ///   - phrase: The phrase to analyze
    ///   - language: Language code ("en", "sv", etc.)
    /// - Returns: Base difficulty score (1-100+ range)
    @MainActor
    func calculateBaseDifficulty(phrase: String, language: String = "en") -> Int {
        let analysis = NetworkManager.analyzeDifficultyClientSide(phrase: phrase, language: language)
        return Int(analysis.score)
    }
    
    // MARK: - Hint-Adjusted Scoring
    
    /// Applies hint penalty to a base score
    /// - Parameters:
    ///   - baseScore: The original difficulty score
    ///   - hintsUsed: Number of hints used (0-3)
    /// - Returns: Score with hint penalty applied
    func applyHintPenalty(baseScore: Int, hintsUsed: Int) -> Int {
        return GameModel.applyHintPenalty(baseScore: baseScore, hintsUsed: hintsUsed)
    }
    
    /// Calculates final score with hint penalty in one step
    /// - Parameters:
    ///   - phrase: The phrase to score
    ///   - language: Language code
    ///   - hintsUsed: Number of hints used
    /// - Returns: Final score with hint penalty applied
    @MainActor
    func calculateFinalScore(phrase: String, language: String = "en", hintsUsed: Int) -> Int {
        let baseScore = calculateBaseDifficulty(phrase: phrase, language: language)
        return applyHintPenalty(baseScore: baseScore, hintsUsed: hintsUsed)
    }
    
    // MARK: - Score Utilities
    
    /// Calculates score for a specific hint level (used for hint previews)
    /// - Parameters:
    ///   - baseScore: Original difficulty score
    ///   - hintLevel: Target hint level (0-3)
    /// - Returns: Score at that hint level
    func scoreForHintLevel(baseScore: Int, hintLevel: Int) -> Int {
        return applyHintPenalty(baseScore: baseScore, hintsUsed: hintLevel)
    }
    
    /// Calculates next hint score for preview purposes
    /// - Parameters:
    ///   - baseScore: Original difficulty score
    ///   - currentHints: Current number of hints used
    /// - Returns: Score after using one more hint, or nil if at max hints
    func nextHintScore(baseScore: Int, currentHints: Int) -> Int? {
        guard currentHints < 3 else { return nil }
        return applyHintPenalty(baseScore: baseScore, hintsUsed: currentHints + 1)
    }
    
    // MARK: - Fallback Handling
    
    /// Calculates score with fallback logic for stored vs calculated difficulty
    /// - Parameters:
    ///   - storedDifficulty: Pre-calculated difficulty (if available)
    ///   - phrase: Phrase to calculate if no stored difficulty
    ///   - language: Language for calculation
    ///   - hintsUsed: Number of hints used
    /// - Returns: Final score using stored or calculated difficulty
    @MainActor
    func calculateWithFallback(
        storedDifficulty: Int?,
        phrase: String,
        language: String = "en",
        hintsUsed: Int
    ) -> Int {
        let baseScore: Int
        if let stored = storedDifficulty, stored > 0 {
            baseScore = stored
        } else {
            baseScore = calculateBaseDifficulty(phrase: phrase, language: language)
        }
        return applyHintPenalty(baseScore: baseScore, hintsUsed: hintsUsed)
    }
}