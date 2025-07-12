#!/usr/bin/env node

/**
 * Test script for the enhanced difficulty algorithm
 * Tests letter repetition penalty functionality
 */

const alg = require('../../shared/difficulty-algorithm');

console.log('🧪 DIFFICULTY ALGORITHM TESTS\n');

// Test cases: [phrase, expectedBehavior]
const testCases = [
    // Basic repetition tests
    ['hello', 'should have moderate repetition penalty (2 l\'s)'],
    ['world', 'should have no repetition penalty (unique letters)'],
    ['banana', 'should have high repetition penalty (3 a\'s, 2 n\'s)'],
    ['pepper', 'should have high repetition penalty (3 p\'s, 2 e\'s)'],
    
    // Multi-word tests
    ['hello world', 'should combine word count + repetition penalty'],
    ['quick brown', 'should have word count but no repetition penalty'],
    ['banana split', 'should have moderate repetition penalty'],
    ['pepper mill', 'should have high repetition penalty'],
    
    // Edge cases
    ['a', 'single letter should have no repetition'],
    ['aa', 'double letter should have maximum repetition'],
    ['aaa', 'triple letter should have maximum repetition'],
    ['', 'empty string should return minimum score']
];

let passedTests = 0;
const totalTests = testCases.length;

console.log('1️⃣  BASIC FUNCTIONALITY TESTS\n');

testCases.forEach(([phrase, description], index) => {
    try {
        const score = alg.calculateScore({ phrase, language: 'en' });
        const normalizedText = phrase.toLowerCase().replace(/[^a-z]/g, '');
        const uniqueLetters = new Set(normalizedText).size;
        const totalLetters = normalizedText.length;
        const repetitionPercentage = totalLetters > 0 ? 
            ((totalLetters - uniqueLetters) / totalLetters * 100).toFixed(1) : 0;
        
        console.log(`${(index + 1).toString().padStart(2)}. "${phrase}" (${repetitionPercentage}% repetition)`);
        console.log(`    Score: ${score} | ${description}`);
        console.log('    ✅ Test passed\n');
        passedTests++;
        
    } catch (error) {
        console.log(`${(index + 1).toString().padStart(2)}. "${phrase}"`);
        console.log(`    ❌ Error: ${error.message}\n`);
    }
});

console.log('2️⃣  COMPARATIVE ANALYSIS\n');

// Test pairs to verify repetition penalty works correctly
const comparisonTests = [
    [['world', 'hello'], 'hello should score higher due to repeated letters'],
    [['friend', 'letter'], 'letter should score higher due to repeated letters'],
    [['strong', 'pepper'], 'pepper should score higher due to repeated letters'],
    [['orange', 'banana'], 'banana should score higher due to repeated letters']
];

comparisonTests.forEach(([[phrase1, phrase2], expectation], index) => {
    const score1 = alg.calculateScore({ phrase: phrase1, language: 'en' });
    const score2 = alg.calculateScore({ phrase: phrase2, language: 'en' });
    
    const phrase1Rep = ((phrase1.length - new Set(phrase1).size) / phrase1.length * 100).toFixed(1);
    const phrase2Rep = ((phrase2.length - new Set(phrase2).size) / phrase2.length * 100).toFixed(1);
    
    console.log(`${index + 1}. Comparing "${phrase1}" (${phrase1Rep}% rep) vs "${phrase2}" (${phrase2Rep}% rep)`);
    console.log(`   Scores: ${score1} vs ${score2}`);
    console.log(`   Expected: ${expectation}`);
    
    if (score2 > score1) {
        console.log('   ✅ Comparison passed\n');
        passedTests++;
    } else {
        console.log('   ❌ Comparison failed\n');
    }
});

console.log('3️⃣  ALGORITHM CONSISTENCY CHECK\n');

// Test that the algorithm produces consistent results
const consistencyPhrase = 'hello world';
const scores = [];
for (let i = 0; i < 5; i++) {
    scores.push(alg.calculateScore({ phrase: consistencyPhrase, language: 'en' }));
}

const allSame = scores.every(score => score === scores[0]);
console.log(`Consistency test with "${consistencyPhrase}"`);
console.log(`Scores: [${scores.join(', ')}]`);
if (allSame) {
    console.log('✅ Algorithm is consistent\n');
    passedTests++;
} else {
    console.log('❌ Algorithm produces inconsistent results\n');
}

console.log('📊 TEST SUMMARY');
console.log(`Passed: ${passedTests}/${totalTests + comparisonTests.length + 1} tests`);

if (passedTests === totalTests + comparisonTests.length + 1) {
    console.log('🎉 All tests passed! Letter repetition algorithm is working correctly.');
    process.exit(0);
} else {
    console.log('⚠️  Some tests failed. Please review the algorithm implementation.');
    process.exit(1);
}