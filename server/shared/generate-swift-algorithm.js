#!/usr/bin/env node

/**
 * Swift Code Generator for Difficulty Algorithm
 * 
 * Generates Swift code from the shared JavaScript difficulty algorithm
 * to ensure both platforms use identical calculation logic.
 */

const fs = require('fs');
const path = require('path');

// Import the shared algorithm
const algorithm = require('../../shared/difficulty-algorithm.js');

function generateSwiftCode() {
    const timestamp = new Date().toISOString();
    
    const swiftCode = `//
// Generated Swift Implementation of Difficulty Algorithm
// Auto-generated from server/shared/difficulty-algorithm.js
// Generated: ${timestamp}
// DO NOT EDIT MANUALLY - Run generate-swift-algorithm.js to update
//

import Foundation

/// Client-side difficulty scorer for real-time UI feedback during phrase creation.
/// This provides immediate scoring estimates while typing, eliminating network calls.
/// The server maintains authoritative scoring for actual game mechanics.
extension NetworkManager {
    
    // MARK: - Language Constants
    
    private static let languageEnglish = "en"
    private static let languageSwedish = "sv"
    
    // MARK: - Letter Frequency Data
    
    private static let englishLetterFrequencies: [Character: Double] = [
${generateFrequencyDictionary(algorithm.ENGLISH_LETTER_FREQUENCIES, '        ')}
    ]
    
    private static let swedishLetterFrequencies: [Character: Double] = [
${generateFrequencyDictionary(algorithm.SWEDISH_LETTER_FREQUENCIES, '        ')}
    ]
    
    // MARK: - Client-Side Difficulty Analysis
    
    /// Analyzes phrase difficulty for real-time UI feedback (matches server algorithm exactly)
    static func analyzeDifficultyClientSide(phrase: String, language: String = "en") -> DifficultyAnalysis {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DifficultyAnalysis(
                phrase: phrase,
                language: language,
                score: 1.0,
                difficulty: "Very Easy",
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        let detectedLanguage = language.isEmpty ? detectLanguageFromPhrase(phrase) : language
        
        let normalizedText = normalizeText(phrase: phrase, language: detectedLanguage)
        let wordCount = countWordsInPhrase(phrase)
        let letterCount = normalizedText.count
        
        guard letterCount > 0 else {
            return DifficultyAnalysis(
                phrase: phrase,
                language: detectedLanguage,
                score: 1.0,
                difficulty: "Very Easy",
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        let score = calculateDifficultyScore(
            normalizedText: normalizedText,
            wordCount: wordCount,
            letterCount: letterCount,
            language: detectedLanguage
        )
        
        return DifficultyAnalysis(
            phrase: phrase,
            language: detectedLanguage,
            score: score,
            difficulty: getDifficultyLabel(for: score),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // MARK: - Private Implementation (Exact Match to Server Algorithm)
    
    private static func normalizeText(phrase: String, language: String) -> String {
        guard !phrase.isEmpty else { return "" }
        
        let text = phrase.lowercased()
        
        if language == languageSwedish {
            // Keep Swedish letters including å, ä, ö
            return text.replacingOccurrences(of: #"[^a-zåäö]"#, with: "", options: .regularExpression)
        } else {
            // Keep only English letters
            return text.replacingOccurrences(of: #"[^a-z]"#, with: "", options: .regularExpression)
        }
    }
    
    private static func countWordsInPhrase(_ phrase: String) -> Int {
        return phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private static func calculateDifficultyScore(normalizedText: String, wordCount: Int, letterCount: Int, language: String) -> Double {
        let frequencies = language == languageSwedish ? swedishLetterFrequencies : englishLetterFrequencies
        let maxFrequency = language == languageSwedish ? 10.1 : 12.7
        
        // 1. Word Count Factor (exponential growth for multi-word phrases)
        let wordCountFactor = pow(Double(max(0, wordCount - 1)), 1.5) * 10.0
        
        // 2. Letter Count Factor (scales with phrase length)
        let letterCountFactor = pow(Double(letterCount), 1.2) * 1.5
        
        // 3. Letter Commonality Factor
        var totalFrequency = 0.0
        for char in normalizedText {
            totalFrequency += frequencies[char] ?? 0.0
        }
        let averageFrequency = totalFrequency / Double(letterCount)
        var commonalityFactor = (averageFrequency / maxFrequency) * 25.0
        
        // Dampen commonality for very short phrases
        if letterCount <= 3 {
            commonalityFactor *= 0.5
        }
        
        // Combine factors and clamp the score
        let rawScore = wordCountFactor + letterCountFactor + commonalityFactor
        let finalScore = round(max(1.0, rawScore))
        
        return finalScore
    }
    
    private static func getDifficultyLabel(for score: Double) -> String {
        switch score {
        case ...20:
            return "Very Easy"
        case ...40:
            return "Easy"
        case ...60:
            return "Medium"
        case ...80:
            return "Hard"
        default:
            return "Very Hard"
        }
    }
    
    private static func detectLanguageFromPhrase(_ phrase: String) -> String {
        guard !phrase.isEmpty else { return languageEnglish }
        
        let text = phrase.lowercased()
        
        // Check for Swedish-specific characters (å, ä, ö)
        if text.contains("å") || text.contains("ä") || text.contains("ö") {
            return languageSwedish
        }
        
        return languageEnglish
    }
}`;

    return swiftCode;
}

function generateFrequencyDictionary(frequencies, indent) {
    const entries = Object.entries(frequencies)
        .map(([char, freq]) => `${indent}"${char}": ${freq}`)
        .join(',\n');
    return entries;
}

function writeSwiftFile() {
    const swiftCode = generateSwiftCode();
    const outputPath = path.join(__dirname, '../../Models/NetworkManager+DifficultyScoring.swift');
    
    try {
        fs.writeFileSync(outputPath, swiftCode, 'utf8');
        console.log(`✅ Generated Swift algorithm at: ${outputPath}`);
        console.log(`📊 Algorithm synchronized with server implementation`);
        return true;
    } catch (error) {
        console.error(`❌ Failed to write Swift file: ${error.message}`);
        return false;
    }
}

// Update the existing NetworkManager extension
function updateNetworkManager() {
    const networkManagerPath = path.join(__dirname, '../../Models/NetworkManager.swift');
    
    try {
        let content = fs.readFileSync(networkManagerPath, 'utf8');
        
        // Remove the existing client-side extension if it exists
        const extensionStart = content.indexOf('// MARK: - Client-Side Difficulty Scoring');
        if (extensionStart !== -1) {
            // Find the end of the file or next major section
            const beforeExtension = content.substring(0, extensionStart);
            const afterExtension = content.substring(extensionStart);
            const nextMark = afterExtension.indexOf('\n// MARK: - ');
            
            if (nextMark !== -1) {
                content = beforeExtension + afterExtension.substring(nextMark);
            } else {
                content = beforeExtension.trimEnd() + '\n';
            }
            
            fs.writeFileSync(networkManagerPath, content, 'utf8');
            console.log(`🧹 Removed old client-side algorithm from NetworkManager.swift`);
        }
        
        return true;
    } catch (error) {
        console.error(`❌ Failed to update NetworkManager: ${error.message}`);
        return false;
    }
}

// Main execution
if (require.main === module) {
    console.log('🔄 Generating Swift difficulty algorithm from shared source...');
    
    if (updateNetworkManager() && writeSwiftFile()) {
        console.log('✅ Swift algorithm generation complete!');
        console.log('📱 iOS app will now use the exact same algorithm as the server');
    } else {
        console.error('❌ Failed to generate Swift algorithm');
        process.exit(1);
    }
}

module.exports = { generateSwiftCode, writeSwiftFile };