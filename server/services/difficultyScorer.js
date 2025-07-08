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
const ENGLISH_FREQUENCIES = {
    'a': 82, 'b': 15, 'c': 28, 'd': 43, 'e': 127, 'f': 22, 'g': 20, 'h': 61,
    'i': 70, 'j': 2, 'k': 8, 'l': 40, 'm': 24, 'n': 67, 'o': 75, 'p': 19,
    'q': 1, 'r': 60, 's': 63, 't': 91, 'u': 28, 'v': 10, 'w': 24, 'x': 2,
    'y': 20, 'z': 1
};

// Swedish letter frequencies (based on Swedish text corpus)
// Frequency = occurrences per 1000 letters
const SWEDISH_FREQUENCIES = {
    'a': 94, 'b': 13, 'c': 15, 'd': 45, 'e': 101, 'f': 20, 'g': 28, 'h': 21,
    'i': 58, 'j': 6, 'k': 32, 'l': 52, 'm': 35, 'n': 89, 'o': 44, 'p': 18,
    'q': 0, 'r': 84, 's': 68, 't': 77, 'u': 18, 'v': 24, 'w': 1, 'x': 1,
    'y': 7, 'z': 1, 'å': 18, 'ä': 18, 'ö': 13
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
        // Validate inputs
        if (!phrase || typeof phrase !== 'string') {
            console.warn('📊 DIFFICULTY: Invalid phrase provided');
            return 1;
        }
        
        if (!Object.values(LANGUAGES).includes(language)) {
            console.warn(`📊 DIFFICULTY: Unknown language '${language}', defaulting to English`);
            language = LANGUAGES.ENGLISH;
        }
        
        // Get appropriate frequency table
        const frequencies = language === LANGUAGES.SWEDISH ? SWEDISH_FREQUENCIES : ENGLISH_FREQUENCIES;
        
        // Normalize the phrase
        const normalizedText = normalize(phrase, language);
        
        if (normalizedText.length === 0) {
            console.warn('📊 DIFFICULTY: No valid letters found in phrase');
            return 1;
        }
        
        // Calculate component scores
        const rarityScore = calculateLetterRarity(normalizedText, frequencies);
        const complexityScore = calculateStructuralComplexity(normalizedText);
        
        // Weighted combination: 70% rarity + 30% complexity
        const combinedScore = (rarityScore * 0.7) + (complexityScore * 0.3);
        
        // Normalize to 1-100 scale
        // Empirical scaling based on typical ranges:
        // - Rarity scores typically range 10-100
        // - Complexity scores typically range 20-80
        // - Combined scores typically range 15-95
        const normalizedScore = Math.max(1, Math.min(100, Math.round(combinedScore)));
        
        console.log(`📊 DIFFICULTY: "${phrase}" (${language}) -> Score: ${normalizedScore} (rarity: ${rarityScore.toFixed(1)}, complexity: ${complexityScore.toFixed(1)})`);
        
        return normalizedScore;
        
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

// Export the module
module.exports = {
    LANGUAGES,
    calculateScore,
    analyzePhrases,
    getDifficultyLabel,
    
    // Export for testing purposes
    normalize,
    calculateLetterRarity,
    calculateStructuralComplexity,
    ENGLISH_FREQUENCIES,
    SWEDISH_FREQUENCIES
};