/**
 * Anagram Game - Difficulty Scoring System
 * 
 * Server-side statistical difficulty scoring for anagram phrases.
 * Uses letter rarity and structural complexity analysis.
 * 
 * Algorithm: (Letter Rarity Score * 0.7) + (Structural Complexity Score * 0.3)
 * Output: Normalized score from 1-100
 */

// Language constants
const LANGUAGES = {
    ENGLISH: 'en',
    SWEDISH: 'sv'
};

// English letter frequencies (based on typical English text)
// Frequency = occurrences per 1000 letters
const ENGLISH_LETTER_FREQUENCIES = {
    'e': 12.7, 't': 9.1, 'a': 8.2, 'o': 7.5, 'i': 7.0, 'n': 6.7, 's': 6.3, 'h': 6.1, 'r': 6.0,
    'd': 4.3, 'l': 4.0, 'c': 2.8, 'u': 2.8, 'm': 2.4, 'w': 2.4, 'f': 2.2, 'g': 2.0, 'y': 2.0,
    'p': 1.9, 'b': 1.5, 'v': 1.0, 'k': 0.8, 'j': 0.2, 'x': 0.2, 'q': 0.1, 'z': 0.1
};

// Swedish letter frequencies (percentage-based)
const SWEDISH_LETTER_FREQUENCIES = {
    'e': 10.1, 'a': 9.4, 'n': 8.9, 't': 8.7, 'r': 8.4, 's': 6.8, 'l': 5.2, 'i': 5.8,
    'd': 4.5, 'o': 4.4, 'k': 3.2, 'g': 2.8, 'm': 3.5, 'h': 2.1, 'f': 2.0, 'v': 2.4,
    'u': 1.8, 'p': 1.8, 'b': 1.3, 'c': 1.5, 'y': 0.7, 'j': 0.6, 'x': 0.1, 'w': 0.1,
    'z': 0.1, 'å': 1.8, 'ä': 1.8, 'ö': 1.3, 'q': 0.01
};

/**
 * Normalizes a phrase by converting to lowercase and keeping only letters
 * @param {string} phrase - The phrase to normalize
 * @param {string} language - Language code ('en' or 'sv')
 * @returns {string} Normalized text containing only lowercase letters
 */
function normalize(phrase, language) {
    if (!phrase || typeof phrase !== 'string') {
        return '';
    }
    
    const text = phrase.toLowerCase();
    
    if (language === LANGUAGES.SWEDISH) {
        // Keep Swedish letters including å, ä, ö
        return text.replace(/[^a-zåäö]/g, '');
    } else {
        // Keep only English letters
        return text.replace(/[^a-z]/g, '');
    }
}

/**
 * Calculates letter rarity score based on frequency analysis
 * @param {string} text - Normalized text to analyze
 * @param {Object} frequencies - Letter frequency table
 * @returns {number} Rarity score (higher = more rare)
 */
function calculateLetterRarity(text, frequencies) {
    if (!text || text.length === 0) {
        return 0;
    }
    
    let totalRarity = 0;
    let letterCount = 0;
    
    for (const char of text) {
        const frequency = frequencies[char] || 1; // Default frequency for unknown letters
        const rarity = 1000 / frequency; // Inverse frequency = rarity
        totalRarity += rarity;
        letterCount++;
    }
    
    return letterCount > 0 ? totalRarity / letterCount : 0;
}

/**
 * Calculates structural complexity based on bigram (letter pair) analysis
 * @param {string} text - Normalized text to analyze
 * @returns {number} Complexity score (higher = more complex)
 */
function calculateStructuralComplexity(text) {
    if (!text || text.length < 2) {
        return 0;
    }
    
    const bigrams = new Set();
    let totalBigrams = 0;
    
    // Extract all letter pairs (bigrams)
    for (let i = 0; i < text.length - 1; i++) {
        const bigram = text.slice(i, i + 2);
        bigrams.add(bigram);
        totalBigrams++;
    }
    
    // Complexity = unique bigrams / total bigrams
    // Higher ratio = more varied structure = higher complexity
    return totalBigrams > 0 ? (bigrams.size / totalBigrams) * 100 : 0;
}

/**
 * Main scoring function - calculates difficulty score for a phrase
 * @param {Object} params - Parameters object
 * @param {string} params.phrase - The phrase to score
 * @param {string} params.language - Language code ('en' or 'sv')
 * @returns {number} Difficulty score from 1-100
 */
function calculateScore({ phrase, language = LANGUAGES.ENGLISH }) {
    try {
        if (!phrase || typeof phrase !== 'string' || phrase.trim().length === 0) {
            console.warn('📊 DIFFICULTY: Invalid or empty phrase provided');
            return 1;
        }

        if (!Object.values(LANGUAGES).includes(language)) {
            console.warn(`📊 DIFFICULTY: Unknown language '${language}', defaulting to English`);
            language = LANGUAGES.ENGLISH;
        }

        const frequencies = language === LANGUAGES.SWEDISH ? SWEDISH_LETTER_FREQUENCIES : ENGLISH_LETTER_FREQUENCIES;
        const maxFrequency = language === LANGUAGES.SWEDISH ? 10.1 : 12.7; // Max freq for 'e' in each language

        const words = phrase.trim().split(/\s+/);
        const wordCount = words.length;

        const normalizedText = normalize(phrase, language);
        const letterCount = normalizedText.length;

        if (letterCount === 0) {
            return 1;
        }

        // 1. Word Count Factor
        const wordCountFactor = Math.pow(Math.max(0, wordCount - 1), 1.5) * 10;

        // 2. Letter Count Factor
        const letterCountFactor = Math.pow(letterCount, 1.2) * 1.5;

        // 3. Letter Commonality Factor
        let totalFrequency = 0;
        for (const char of normalizedText) {
            totalFrequency += frequencies[char] || 0;
        }
        const averageFrequency = totalFrequency / letterCount;
        let commonalityFactor = (averageFrequency / maxFrequency) * 25;

        // Dampen commonality for very short phrases
        if (letterCount <= 3) {
            commonalityFactor *= 0.5;
        }
        
        // Combine factors and clamp the score
        const rawScore = wordCountFactor + letterCountFactor + commonalityFactor;
        const finalScore = Math.round(Math.max(1, rawScore));

        console.log(`📊 NEW DIFFICULTY: "${phrase}" (${language}) -> Score: ${finalScore} (words: ${wordCount}, letters: ${letterCount}, commonality: ${commonalityFactor.toFixed(1)})`);

        return finalScore;

    } catch (error) {
        console.error('📊 DIFFICULTY: Error calculating score:', error.message);
        return 1; // Return minimum score on error
    }
}

/**
 * Analyzes multiple phrases and returns detailed scoring information
 * @param {Array} phrases - Array of phrase objects with {phrase, language}
 * @returns {Array} Array of results with scoring details
 */
function analyzePhrases(phrases) {
    if (!Array.isArray(phrases)) {
        return [];
    }
    
    return phrases.map(item => {
        const score = calculateScore(item);
        return {
            phrase: item.phrase,
            language: item.language || LANGUAGES.ENGLISH,
            score: score,
            difficulty: getDifficultyLabel(score)
        };
    });
}

/**
 * Converts numeric score to difficulty label
 * @param {number} score - Score from 1-100
 * @returns {string} Difficulty label
 */
function getDifficultyLabel(score) {
    if (score <= 20) return 'Very Easy';
    if (score <= 40) return 'Easy';
    if (score <= 60) return 'Medium';
    if (score <= 80) return 'Hard';
    return 'Very Hard';
}

/**
 * Auto-detect language from phrase content
 * @param {string} phrase - The phrase to analyze
 * @returns {string} Language code ('en' or 'sv')
 */
function detectLanguage(phrase) {
    if (!phrase || typeof phrase !== 'string') {
        return LANGUAGES.ENGLISH;
    }
    
    const text = phrase.toLowerCase();
    
    // Check for Swedish-specific characters (å, ä, ö)
    if (/[åäö]/.test(text)) {
        return LANGUAGES.SWEDISH;
    }
    
    // If no Swedish characters, default to English
    return LANGUAGES.ENGLISH;
}

// Export the module
module.exports = {
    LANGUAGES,
    calculateScore,
    analyzePhrases,
    getDifficultyLabel,
    detectLanguage,
    
    // Export for testing purposes
    normalize,
    ENGLISH_LETTER_FREQUENCIES,
    SWEDISH_LETTER_FREQUENCIES
};