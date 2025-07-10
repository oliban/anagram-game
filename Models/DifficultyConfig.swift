import Foundation

/// Configuration-based difficulty scoring system
/// Reads shared configuration to ensure identical scoring with server
class DifficultyConfig {
    static let shared = DifficultyConfig()
    
    // MARK: - Configuration Structure
    
    let version: String
    let lastUpdated: String
    let languages: Languages
    let letterFrequencies: [String: [String: Double]]
    let maxFrequencies: [String: Double]
    let difficultyThresholds: DifficultyThresholds
    let difficultyLabels: DifficultyLabels
    let algorithmParameters: AlgorithmParameters
    let textNormalization: [String: TextNormalization]
    let languageDetection: LanguageDetection
    
    // MARK: - Nested Types
    
    struct Languages: Codable {
        let english: String
        let swedish: String
    }
    
    struct DifficultyThresholds: Codable {
        let veryEasy: Double
        let easy: Double
        let medium: Double
        let hard: Double
    }
    
    struct DifficultyLabels: Codable {
        let veryEasy: String
        let easy: String
        let medium: String
        let hard: String
        let veryHard: String
    }
    
    struct AlgorithmParameters: Codable {
        let wordCount: WordCountParameters
        let letterCount: LetterCountParameters
        let commonality: CommonalityParameters
        let minimumScore: Double
        
        struct WordCountParameters: Codable {
            let exponent: Double
            let multiplier: Double
        }
        
        struct LetterCountParameters: Codable {
            let exponent: Double
            let multiplier: Double
        }
        
        struct CommonalityParameters: Codable {
            let multiplier: Double
            let shortPhraseThreshold: Int
            let shortPhraseDampening: Double
        }
    }
    
    struct TextNormalization: Codable {
        let regex: String
        let description: String
    }
    
    struct LanguageDetection: Codable {
        let swedishCharacters: String
        let defaultLanguage: String
    }
    
    // MARK: - Configuration Container
    
    private struct ConfigurationContainer: Codable {
        let version: String
        let lastUpdated: String
        let languages: Languages
        let letterFrequencies: [String: [String: Double]]
        let maxFrequencies: [String: Double]
        let difficultyThresholds: DifficultyThresholds
        let difficultyLabels: DifficultyLabels
        let algorithmParameters: AlgorithmParameters
        let textNormalization: [String: TextNormalization]
        let languageDetection: LanguageDetection
    }
    
    // MARK: - Initialization
    
    private init?() {
        guard let configPath = Bundle.main.path(forResource: "difficulty-algorithm-config", ofType: "json"),
              let configData = NSData(contentsOfFile: configPath) as Data? else {
            print("❌ DIFFICULTY CONFIG: Could not find difficulty-algorithm-config.json in app bundle")
            return nil
        }
        
        do {
            let container = try JSONDecoder().decode(ConfigurationContainer.self, from: configData)
            
            self.version = container.version
            self.lastUpdated = container.lastUpdated
            self.languages = container.languages
            self.letterFrequencies = container.letterFrequencies
            self.maxFrequencies = container.maxFrequencies
            self.difficultyThresholds = container.difficultyThresholds
            self.difficultyLabels = container.difficultyLabels
            self.algorithmParameters = container.algorithmParameters
            self.textNormalization = container.textNormalization
            self.languageDetection = container.languageDetection
            
            print("✅ DIFFICULTY CONFIG: Loaded version \(version) from \(lastUpdated)")
            
        } catch {
            print("❌ DIFFICULTY CONFIG: Failed to decode configuration: \(error)")
            return nil
        }
    }
    
    // MARK: - Public API
    
    /// Normalizes text according to language rules
    func normalize(phrase: String, language: String) -> String {
        guard !phrase.isEmpty else { return "" }
        
        let text = phrase.lowercased()
        let normalizationRule = textNormalization[language] ?? textNormalization[languages.english]!
        
        return text.replacingOccurrences(of: normalizationRule.regex, with: "", options: .regularExpression)
    }
    
    /// Detects language from phrase content
    func detectLanguage(_ phrase: String) -> String {
        guard !phrase.isEmpty else { return languageDetection.defaultLanguage }
        
        let text = phrase.lowercased()
        
        // Check for Swedish-specific characters
        if text.range(of: languageDetection.swedishCharacters, options: .regularExpression) != nil {
            return languages.swedish
        }
        
        return languageDetection.defaultLanguage
    }
    
    /// Calculates difficulty score using configuration parameters
    func calculateScore(normalizedText: String, wordCount: Int, letterCount: Int, language: String) -> Double {
        let frequencies = letterFrequencies[language] ?? letterFrequencies[languages.english]!
        let maxFrequency = maxFrequencies[language] ?? maxFrequencies[languages.english]!
        
        // 1. Word Count Factor
        let wordCountFactor = pow(
            Double(max(0, wordCount - 1)),
            algorithmParameters.wordCount.exponent
        ) * algorithmParameters.wordCount.multiplier
        
        // 2. Letter Count Factor
        let letterCountFactor = pow(
            Double(letterCount),
            algorithmParameters.letterCount.exponent
        ) * algorithmParameters.letterCount.multiplier
        
        // 3. Letter Commonality Factor
        var totalFrequency = 0.0
        for char in normalizedText {
            totalFrequency += frequencies[String(char)] ?? 0.0
        }
        let averageFrequency = totalFrequency / Double(letterCount)
        var commonalityFactor = (averageFrequency / maxFrequency) * algorithmParameters.commonality.multiplier
        
        // Dampen commonality for very short phrases
        if letterCount <= algorithmParameters.commonality.shortPhraseThreshold {
            commonalityFactor *= algorithmParameters.commonality.shortPhraseDampening
        }
        
        // Combine factors and clamp the score
        let rawScore = wordCountFactor + letterCountFactor + commonalityFactor
        let finalScore = round(max(algorithmParameters.minimumScore, rawScore))
        
        return finalScore
    }
    
    /// Gets difficulty label for numeric score
    func getDifficultyLabel(for score: Double) -> String {
        switch score {
        case ...difficultyThresholds.veryEasy:
            return difficultyLabels.veryEasy
        case ...difficultyThresholds.easy:
            return difficultyLabels.easy
        case ...difficultyThresholds.medium:
            return difficultyLabels.medium
        case ...difficultyThresholds.hard:
            return difficultyLabels.hard
        default:
            return difficultyLabels.veryHard
        }
    }
}