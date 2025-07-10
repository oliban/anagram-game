/**
 * Anagram Game - Difficulty Scoring System (Server Wrapper)
 * 
 * Server-side wrapper for the shared difficulty algorithm.
 * Imports the shared algorithm to ensure consistency with client-side scoring.
 */

// Import the shared algorithm
const sharedAlgorithm = require('../../shared/difficulty-algorithm');

// Re-export all functions from the shared algorithm
module.exports = sharedAlgorithm;