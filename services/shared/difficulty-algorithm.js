/**
 * Shared Difficulty Analysis Algorithm
 * 
 * This algorithm reads from difficulty-algorithm-config.json to ensure
 * both iOS client and Node.js server use identical calculation logic.
 * 
 * Version: 1.0.0 (Configuration-based)
 */

const fs = require('fs');
const path = require('path');

// Load configuration
const configPath = path.join(__dirname, 'difficulty-algorithm-config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

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
    const normalizationRule = config.textNormalization[language] || config.textNormalization.en;
    
    return text.replace(new RegExp(normalizationRule.regex, 'g'), '');
}

/**
 * Auto-detect language from phrase content
 * @param {string} phrase - The phrase to analyze
 * @returns {string} Language code ('en' or 'sv')
 */
function detectLanguage(phrase) {
    if (!phrase || typeof phrase !== 'string') {
        return config.languageDetection.defaultLanguage;
    }
    
    const text = phrase.toLowerCase();
    
    // Check for Swedish-specific characters
    if (new RegExp(config.languageDetection.swedishCharacters).test(text)) {
        return config.languages.swedish;
    }
    
    return config.languageDetection.defaultLanguage;
}

/**
 * Main scoring function - calculates difficulty score for a phrase
 * @param {Object} params - Parameters object
 * @param {string} params.phrase - The phrase to score
 * @param {string} params.language - Language code ('en' or 'sv')
 * @returns {number} Difficulty score from 1-100
 */
function calculateScore({ phrase, language = config.languages.english }) {
    try {
        if (!phrase || typeof phrase !== 'string' || phrase.trim().length === 0) {
            console.warn('📊 DIFFICULTY: Invalid or empty phrase provided');
            return config.algorithmParameters.minimumScore;
        }

        if (!Object.values(config.languages).includes(language)) {
            console.warn(`📊 DIFFICULTY: Unknown language '${language}', defaulting to English`);
            language = config.languages.english;
        }

        const frequencies = config.letterFrequencies[language];
        const maxFrequency = config.maxFrequencies[language];

        const words = phrase.trim().split(/\s+/);
        const wordCount = words.length;

        const normalizedText = normalize(phrase, language);
        const letterCount = normalizedText.length;

        if (letterCount === 0) {
            return config.algorithmParameters.minimumScore;
        }

        // 1. Word Count Factor
        const wordCountFactor = Math.pow(
            Math.max(0, wordCount - 1), 
            config.algorithmParameters.wordCount.exponent
        ) * config.algorithmParameters.wordCount.multiplier;

        // 2. Letter Count Factor
        const letterCountFactor = Math.pow(
            letterCount, 
            config.algorithmParameters.letterCount.exponent
        ) * config.algorithmParameters.letterCount.multiplier;

        // 3. Letter Commonality Factor
        let totalFrequency = 0;
        for (const char of normalizedText) {
            totalFrequency += frequencies[char] || 0;
        }
        const averageFrequency = totalFrequency / letterCount;
        let commonalityFactor = (averageFrequency / maxFrequency) * config.algorithmParameters.commonality.multiplier;

        // Dampen commonality for very short phrases
        if (letterCount <= config.algorithmParameters.commonality.shortPhraseThreshold) {
            commonalityFactor *= config.algorithmParameters.commonality.shortPhraseDampening;
        }

        // 4. Letter Repetition Factor
        const uniqueLetters = new Set(normalizedText).size;
        const repetitionRatio = (letterCount - uniqueLetters) / letterCount;
        const repetitionFactor = repetitionRatio * config.algorithmParameters.letterRepetition.multiplier;
        
        // Combine factors and clamp the score
        const rawScore = wordCountFactor + letterCountFactor + commonalityFactor + repetitionFactor;
        const finalScore = Math.round(Math.max(config.algorithmParameters.minimumScore, rawScore));

        console.log(`📊 NEW DIFFICULTY: "${phrase}" (${language}) -> Score: ${finalScore} (words: ${wordCount}, letters: ${letterCount}, commonality: ${commonalityFactor.toFixed(1)}, repetition: ${repetitionFactor.toFixed(1)})`);

        return finalScore;

    } catch (error) {
        console.error('📊 DIFFICULTY: Error calculating score:', error.message);
        return config.algorithmParameters.minimumScore;
    }
}

/**
 * Converts numeric score to difficulty label
 * @param {number} score - Score from 1-100
 * @returns {string} Difficulty label
 */
function getDifficultyLabel(score) {
    const thresholds = config.difficultyThresholds;
    const labels = config.difficultyLabels;
    
    if (score <= thresholds.veryEasy) return labels.veryEasy;
    if (score <= thresholds.easy) return labels.easy;
    if (score <= thresholds.medium) return labels.medium;
    if (score <= thresholds.hard) return labels.hard;
    return labels.veryHard;
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
            language: item.language || config.languages.english,
            score: score,
            difficulty: getDifficultyLabel(score)
        };
    });
}

// Export the module
module.exports = {
    config,
    LANGUAGES: config.languages,
    calculateScore,
    analyzePhrases,
    getDifficultyLabel,
    // detectLanguage removed - use explicit language parameter
    
    // Export for testing purposes
    normalize,
    ENGLISH_LETTER_FREQUENCIES: config.letterFrequencies.en,
    SWEDISH_LETTER_FREQUENCIES: config.letterFrequencies.sv
};