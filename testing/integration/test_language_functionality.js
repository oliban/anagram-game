const { detectLanguage } = require('./services/difficultyScorer');

class LanguageFunctionalityTests {
  constructor() {
    this.testResults = [];
  }

  logResult(testName, passed, details = '') {
    const status = passed ? '✅' : '❌';
    console.log(`${status} ${testName}: ${details}`);
    this.testResults.push({ testName, passed, details });
  }

  async runAllTests() {
    console.log('\n🔬 Starting Language Functionality Tests...\n');

    try {
      this.testSwedishDetection();
      this.testEnglishDetection();
      this.testMixedContent();
      this.testEdgeCases();
      
      this.printSummary();
    } catch (error) {
      console.error('❌ Test suite failed:', error.message);
      return false;
    }
  }

  testSwedishDetection() {
    const swedishPhrases = [
      'Hej världen',
      'Ett förhållande',
      'Kött och potatis',
      'Jag älskar dig',
      'Röd häst'
    ];

    swedishPhrases.forEach((phrase, index) => {
      const detected = detectLanguage(phrase);
      const passed = detected === 'sv';
      this.logResult(
        `Swedish detection ${index + 1}`, 
        passed, 
        `"${phrase}" → ${detected}`
      );
    });
  }

  testEnglishDetection() {
    const englishPhrases = [
      'Hello world',
      'The quick brown fox',
      'Amazing test phrase',
      'Beautiful sunny day',
      'Computer programming'
    ];

    englishPhrases.forEach((phrase, index) => {
      const detected = detectLanguage(phrase);
      const passed = detected === 'en';
      this.logResult(
        `English detection ${index + 1}`, 
        passed, 
        `"${phrase}" → ${detected}`
      );
    });
  }

  testMixedContent() {
    const mixedPhrases = [
      { phrase: 'Hello världen', expected: 'sv' }, // Should detect Swedish due to ä
      { phrase: 'Hej world', expected: 'en' }, // Should detect English (no Swedish chars)
      { phrase: 'Test ö phrase', expected: 'sv' }, // Should detect Swedish due to ö
      { phrase: 'åäö', expected: 'sv' }, // All Swedish chars
      { phrase: 'xyz abc', expected: 'en' } // No Swedish chars
    ];

    mixedPhrases.forEach((test, index) => {
      const detected = detectLanguage(test.phrase);
      const passed = detected === test.expected;
      this.logResult(
        `Mixed content ${index + 1}`, 
        passed, 
        `"${test.phrase}" → ${detected} (expected ${test.expected})`
      );
    });
  }

  testEdgeCases() {
    const edgeCases = [
      { phrase: '', expected: 'en' },
      { phrase: null, expected: 'en' },
      { phrase: undefined, expected: 'en' },
      { phrase: '123 456', expected: 'en' },
      { phrase: '!@# $%^', expected: 'en' },
      { phrase: 'Å', expected: 'sv' }
    ];

    edgeCases.forEach((test, index) => {
      const detected = detectLanguage(test.phrase);
      const passed = detected === test.expected;
      this.logResult(
        `Edge case ${index + 1}`, 
        passed, 
        `"${test.phrase}" → ${detected} (expected ${test.expected})`
      );
    });
  }

  printSummary() {
    const passed = this.testResults.filter(r => r.passed).length;
    const total = this.testResults.length;
    const successRate = ((passed / total) * 100).toFixed(1);

    console.log(`\n📊 Language Functionality Test Summary:`);
    console.log(`✅ Passed: ${passed}/${total} (${successRate}%)`);
    
    if (passed === total) {
      console.log('🎉 All language functionality tests passed!');
      return true;
    } else {
      console.log('❌ Some language functionality tests failed');
      return false;
    }
  }
}

// Run tests if this file is executed directly
if (require.main === module) {
  const tests = new LanguageFunctionalityTests();
  tests.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  });
}

module.exports = LanguageFunctionalityTests;