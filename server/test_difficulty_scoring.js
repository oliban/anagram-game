/**
 * Test Suite for Difficulty Scoring System
 * Tests the statistical difficulty analysis for anagram phrases
 */

const { calculateScore, analyzePhrases, getDifficultyLabel, LANGUAGES, normalize, calculateLetterRarity, calculateStructuralComplexity, ENGLISH_FREQUENCIES, SWEDISH_FREQUENCIES } = require('./services/difficultyScorer');

// Test data sets
const TEST_PHRASES = {
  english: [
    { phrase: "a", expected: { min: 1, max: 30 } },           // Very simple
    { phrase: "hello world", expected: { min: 35, max: 55 } }, // Medium
    { phrase: "the quick brown fox jumps", expected: { min: 80, max: 100 } }, // Very Hard (contains 'q', 'x')
    { phrase: "extraordinary phenomenon", expected: { min: 50, max: 80 } }, // Hard
    { phrase: "quiz", expected: { min: 60, max: 100 } },      // Very hard (rare letters)
    { phrase: "abcdefghijklmnop", expected: { min: 70, max: 85 } }, // High structural complexity + rare letters
    { phrase: "programming", expected: { min: 30, max: 60 } }, // Repeated letters
    { phrase: "test", expected: { min: 20, max: 50 } }        // Common letters
  ],
  swedish: [
    { phrase: "hej världen", expected: { min: 30, max: 60 } }, // Hello world in Swedish
    { phrase: "kött", expected: { min: 40, max: 70 } },       // Swedish specific letters
    { phrase: "ö å ä", expected: { min: 50, max: 80 } },      // Swedish vowels
    { phrase: "test", expected: { min: 20, max: 50 } }        // Same as English
  ]
};

function runAllTests() {
  console.log('🧪 TESTING: Starting Difficulty Scoring System Tests\n');
  
  let totalTests = 0;
  let passedTests = 0;
  
  // Test helper functions
  console.log('📋 Testing Helper Functions:');
  
  // Test normalize function
  console.log('  Testing normalize():');
  totalTests++;
  const normalized = normalize("Hello, World! 123", LANGUAGES.ENGLISH);
  if (normalized === "helloworld") {
    console.log('    ✅ Normalize: English text correctly normalized');
    passedTests++;
  } else {
    console.log(`    ❌ Normalize: Expected "helloworld", got "${normalized}"`);
  }
  
  totalTests++;
  const normalizedSwedish = normalize("Hej, Världen! åäö", LANGUAGES.SWEDISH);
  if (normalizedSwedish === "hejvärldenåäö") {
    console.log('    ✅ Normalize: Swedish text correctly normalized');
    passedTests++;
  } else {
    console.log(`    ❌ Normalize: Expected "hejvärldenåäö", got "${normalizedSwedish}"`);
  }
  
  // Test letter rarity calculation
  console.log('  Testing calculateLetterRarity():');
  totalTests++;
  const rarityCommon = calculateLetterRarity("eee", ENGLISH_FREQUENCIES); // Very common letter
  const rarityRare = calculateLetterRarity("zzz", ENGLISH_FREQUENCIES);   // Very rare letter
  if (rarityRare > rarityCommon) {
    console.log('    ✅ Letter Rarity: Rare letters scored higher than common letters');
    passedTests++;
  } else {
    console.log(`    ❌ Letter Rarity: Rare (${rarityRare}) should be > Common (${rarityCommon})`);
  }
  
  // Test structural complexity
  console.log('  Testing calculateStructuralComplexity():');
  totalTests++;
  const complexitySimple = calculateStructuralComplexity("aaa");     // Repeated letters
  const complexityComplex = calculateStructuralComplexity("abcde");  // All different
  if (complexityComplex > complexitySimple) {
    console.log('    ✅ Structural Complexity: Varied text scored higher than repetitive text');
    passedTests++;
  } else {
    console.log(`    ❌ Structural Complexity: Complex (${complexityComplex}) should be > Simple (${complexitySimple})`);
  }
  
  console.log('');
  
  // Test main scoring function
  console.log('📊 Testing Main Scoring Function:');
  
  // Test English phrases
  console.log('  Testing English phrases:');
  for (const testCase of TEST_PHRASES.english) {
    totalTests++;
    const score = calculateScore({ phrase: testCase.phrase, language: LANGUAGES.ENGLISH });
    
    if (score >= testCase.expected.min && score <= testCase.expected.max) {
      console.log(`    ✅ "${testCase.phrase}": Score ${score} (within expected range ${testCase.expected.min}-${testCase.expected.max})`);
      passedTests++;
    } else {
      console.log(`    ❌ "${testCase.phrase}": Score ${score} (expected ${testCase.expected.min}-${testCase.expected.max})`);
    }
  }
  
  // Test Swedish phrases
  console.log('  Testing Swedish phrases:');
  for (const testCase of TEST_PHRASES.swedish) {
    totalTests++;
    const score = calculateScore({ phrase: testCase.phrase, language: LANGUAGES.SWEDISH });
    
    if (score >= testCase.expected.min && score <= testCase.expected.max) {
      console.log(`    ✅ "${testCase.phrase}": Score ${score} (within expected range ${testCase.expected.min}-${testCase.expected.max})`);
      passedTests++;
    } else {
      console.log(`    ❌ "${testCase.phrase}": Score ${score} (expected ${testCase.expected.min}-${testCase.expected.max})`);
    }
  }
  
  console.log('');
  
  // Test error handling
  console.log('🛡️ Testing Error Handling:');
  
  totalTests++;
  const emptyScore = calculateScore({ phrase: "", language: LANGUAGES.ENGLISH });
  if (emptyScore === 1) {
    console.log('    ✅ Empty phrase: Returns minimum score (1)');
    passedTests++;
  } else {
    console.log(`    ❌ Empty phrase: Expected 1, got ${emptyScore}`);
  }
  
  totalTests++;
  const nullScore = calculateScore({ phrase: null, language: LANGUAGES.ENGLISH });
  if (nullScore === 1) {
    console.log('    ✅ Null phrase: Returns minimum score (1)');
    passedTests++;
  } else {
    console.log(`    ❌ Null phrase: Expected 1, got ${nullScore}`);
  }
  
  totalTests++;
  const invalidLangScore = calculateScore({ phrase: "test", language: "invalid" });
  if (invalidLangScore >= 1 && invalidLangScore <= 100) {
    console.log('    ✅ Invalid language: Falls back to English and returns valid score');
    passedTests++;
  } else {
    console.log(`    ❌ Invalid language: Expected valid score, got ${invalidLangScore}`);
  }
  
  console.log('');
  
  // Test difficulty labels
  console.log('🏷️ Testing Difficulty Labels:');
  
  const labelTests = [
    { score: 10, expected: "Very Easy" },
    { score: 30, expected: "Easy" },
    { score: 50, expected: "Medium" },
    { score: 70, expected: "Hard" },
    { score: 90, expected: "Very Hard" }
  ];
  
  for (const test of labelTests) {
    totalTests++;
    const label = getDifficultyLabel(test.score);
    if (label === test.expected) {
      console.log(`    ✅ Score ${test.score}: "${label}"`);
      passedTests++;
    } else {
      console.log(`    ❌ Score ${test.score}: Expected "${test.expected}", got "${label}"`);
    }
  }
  
  console.log('');
  
  // Test multiple phrase analysis
  console.log('📊 Testing Batch Analysis:');
  
  totalTests++;
  const batchPhrases = [
    { phrase: "hello", language: LANGUAGES.ENGLISH },
    { phrase: "world", language: LANGUAGES.ENGLISH },
    { phrase: "hej", language: LANGUAGES.SWEDISH }
  ];
  
  const batchResults = analyzePhrases(batchPhrases);
  if (batchResults.length === 3 && batchResults.every(r => r.score >= 1 && r.score <= 100)) {
    console.log('    ✅ Batch analysis: All phrases analyzed correctly');
    passedTests++;
  } else {
    console.log('    ❌ Batch analysis: Unexpected results');
    console.log('      Results:', batchResults);
  }
  
  console.log('');
  
  // Test scoring consistency
  console.log('🔄 Testing Scoring Consistency:');
  
  totalTests++;
  const phrase = "consistency test";
  const score1 = calculateScore({ phrase, language: LANGUAGES.ENGLISH });
  const score2 = calculateScore({ phrase, language: LANGUAGES.ENGLISH });
  const score3 = calculateScore({ phrase, language: LANGUAGES.ENGLISH });
  
  if (score1 === score2 && score2 === score3) {
    console.log(`    ✅ Consistency: Same phrase always returns same score (${score1})`);
    passedTests++;
  } else {
    console.log(`    ❌ Consistency: Scores vary: ${score1}, ${score2}, ${score3}`);
  }
  
  console.log('');
  
  // Test score distribution
  console.log('📈 Testing Score Distribution:');
  
  const distributionPhrases = [
    "a", "be", "cat", "dog", "hello", "world", "testing", "programming", 
    "extraordinary", "quiz", "complex", "simple", "medium", "difficult"
  ];
  
  const scores = distributionPhrases.map(phrase => 
    calculateScore({ phrase, language: LANGUAGES.ENGLISH })
  );
  
  const minScore = Math.min(...scores);
  const maxScore = Math.max(...scores);
  const avgScore = scores.reduce((sum, score) => sum + score, 0) / scores.length;
  
  totalTests++;
  if (minScore >= 1 && maxScore <= 100 && maxScore > minScore) {
    console.log(`    ✅ Score Range: Min=${minScore}, Max=${maxScore}, Avg=${avgScore.toFixed(1)}`);
    passedTests++;
  } else {
    console.log(`    ❌ Score Range: Invalid distribution - Min=${minScore}, Max=${maxScore}`);
  }
  
  // Final results
  console.log('='.repeat(60));
  console.log('📊 TEST RESULTS:');
  console.log(`   Total Tests: ${totalTests}`);
  console.log(`   Passed: ${passedTests}`);
  console.log(`   Failed: ${totalTests - passedTests}`);
  console.log(`   Success Rate: ${((passedTests / totalTests) * 100).toFixed(1)}%`);
  
  if (passedTests === totalTests) {
    console.log('   🎉 ALL TESTS PASSED!');
    return true;
  } else {
    console.log('   ⚠️ Some tests failed');
    return false;
  }
}

// Export for use in other test files
module.exports = {
  runAllTests,
  TEST_PHRASES
};

// Run tests if this file is executed directly
if (require.main === module) {
  const success = runAllTests();
  process.exit(success ? 0 : 1);
}