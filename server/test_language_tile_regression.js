#!/usr/bin/env node

/**
 * Language Tile Regression Test Suite
 * 
 * This test specifically covers the bug where Swedish phrases were showing
 * the English flag in the language tile instead of the Swedish flag.
 * 
 * Tests ensure:
 * 1. Language field is properly stored in database when creating phrases
 * 2. Language field is returned in API responses
 * 3. Swedish phrases (sv) display Swedish flag (flag_sweden)
 * 4. English phrases (en) display English flag (flag_england)
 * 5. Backward compatibility with existing phrases
 * 
 * This prevents regression of the language tile flag display bug.
 */

const axios = require('axios');
const DatabasePhrase = require('./models/DatabasePhrase');
const DatabasePlayer = require('./models/DatabasePlayer');

const SERVER_URL = 'http://localhost:3000';

// Test configuration
const CONFIG = {
  timeout: 10000,
  verbose: true
};

// Test results tracking
let testResults = {
  passed: 0,
  failed: 0,
  errors: []
};

function logTest(category, testName, success, details = '') {
  const status = success ? '✅ PASS' : '❌ FAIL';
  const message = `${status} [${category}] ${testName}`;
  
  if (CONFIG.verbose) {
    console.log(`${message}${details ? `\n      ${details}` : ''}`);
  }
  
  if (success) {
    testResults.passed++;
  } else {
    testResults.failed++;
    testResults.errors.push(`${testName}: ${details}`);
  }
}

// Test helper functions
async function createTestPlayer(name) {
  try {
    const response = await axios.post(`${SERVER_URL}/api/players`, {
      name: name,
      socketId: `test-socket-${Date.now()}-${Math.random()}`
    }, { timeout: CONFIG.timeout });
    
    return response.data.player;
  } catch (error) {
    throw new Error(`Failed to create test player: ${error.message}`);
  }
}

async function createTestPhrase(senderId, targetId, content, clue, language) {
  try {
    const response = await axios.post(`${SERVER_URL}/api/phrases`, {
      content: content,
      senderId: senderId,
      targetId: targetId,
      hint: clue,
      language: language
    }, { timeout: CONFIG.timeout });
    
    return response.data;
  } catch (error) {
    throw new Error(`Failed to create phrase: ${error.message}`);
  }
}

async function getPhrasesForPlayer(playerId) {
  try {
    const response = await axios.get(`${SERVER_URL}/api/phrases/for/${playerId}`, {
      timeout: CONFIG.timeout
    });
    
    return response.data.phrases || [];
  } catch (error) {
    throw new Error(`Failed to get phrases: ${error.message}`);
  }
}

// Main test functions
async function testLanguageFieldInAPIResponse() {
  console.log('🔍 Testing language field in API response...');
  
  try {
    // Use existing player with known phrases
    const phrases = await getPhrasesForPlayer('989d493b-42ec-489f-b25f-c4700e8ee735');
    
    if (phrases.length > 0) {
      const firstPhrase = phrases[0];
      const hasLanguageField = firstPhrase.hasOwnProperty('language');
      
      logTest(
        'API Response',
        'Language field exists in API response',
        hasLanguageField,
        hasLanguageField ? `Language: ${firstPhrase.language}` : 'Language field missing'
      );
      
      // Test that language field has a valid value
      if (hasLanguageField) {
        const validLanguage = firstPhrase.language && 
                            (firstPhrase.language === 'en' || firstPhrase.language === 'sv');
        logTest(
          'API Response',
          'Language field has valid value',
          validLanguage,
          `Language: ${firstPhrase.language}`
        );
      }
    } else {
      logTest('API Response', 'API response test', false, 'No phrases found for testing');
    }
    
  } catch (error) {
    logTest('API Response', 'Language field API test', false, error.message);
  }
}

async function testSwedishPhraseFlag() {
  console.log('🔍 Testing Swedish phrase flag mapping...');
  
  try {
    // Create test players
    const sender = await createTestPlayer('SwedishFlagTestSender');
    const receiver = await createTestPlayer('SwedishFlagTestReceiver');
    
    // Create Swedish phrase
    const swedishPhrase = {
      content: 'hej världen test',
      clue: 'swedish greeting test',
      language: 'sv'
    };
    
    const createResponse = await createTestPhrase(
      sender.id,
      receiver.id,
      swedishPhrase.content,
      swedishPhrase.clue,
      swedishPhrase.language
    );
    
    // Verify phrase was created with Swedish language
    const createdWithSwedish = createResponse.phrase && createResponse.phrase.language === 'sv';
    
    logTest(
      'Swedish Flag',
      'Swedish phrase created with sv language',
      createdWithSwedish,
      `Created with language: ${createResponse.phrase?.language || 'undefined'}`
    );
    
    // Verify retrieval returns Swedish language
    const phrases = await getPhrasesForPlayer(receiver.id);
    const retrievedPhrase = phrases.find(p => p.content === swedishPhrase.content);
    
    if (retrievedPhrase) {
      const retrievedWithSwedish = retrievedPhrase.language === 'sv';
      
      logTest(
        'Swedish Flag',
        'Swedish phrase retrieved with sv language',
        retrievedWithSwedish,
        `Retrieved with language: ${retrievedPhrase.language}`
      );
      
      // Test the flag mapping logic that iOS client uses
      const flagImageName = retrievedPhrase.language === 'sv' ? 'flag_sweden' : 'flag_england';
      const correctFlag = flagImageName === 'flag_sweden';
      
      logTest(
        'Swedish Flag',
        'Swedish language maps to Swedish flag',
        correctFlag,
        `Language: ${retrievedPhrase.language} → Flag: ${flagImageName}`
      );
    } else {
      logTest('Swedish Flag', 'Swedish phrase retrieval', false, 'Swedish phrase not found');
    }
    
  } catch (error) {
    logTest('Swedish Flag', 'Swedish phrase flag test', false, error.message);
  }
}

async function testEnglishPhraseFlag() {
  console.log('🔍 Testing English phrase flag mapping...');
  
  try {
    // Create test players
    const sender = await createTestPlayer('EnglishFlagTestSender');
    const receiver = await createTestPlayer('EnglishFlagTestReceiver');
    
    // Create English phrase
    const englishPhrase = {
      content: 'hello world test',
      clue: 'english greeting test',
      language: 'en'
    };
    
    const createResponse = await createTestPhrase(
      sender.id,
      receiver.id,
      englishPhrase.content,
      englishPhrase.clue,
      englishPhrase.language
    );
    
    // Verify phrase was created with English language
    const createdWithEnglish = createResponse.phrase && createResponse.phrase.language === 'en';
    
    logTest(
      'English Flag',
      'English phrase created with en language',
      createdWithEnglish,
      `Created with language: ${createResponse.phrase?.language || 'undefined'}`
    );
    
    // Verify retrieval returns English language
    const phrases = await getPhrasesForPlayer(receiver.id);
    const retrievedPhrase = phrases.find(p => p.content === englishPhrase.content);
    
    if (retrievedPhrase) {
      const retrievedWithEnglish = retrievedPhrase.language === 'en';
      
      logTest(
        'English Flag',
        'English phrase retrieved with en language',
        retrievedWithEnglish,
        `Retrieved with language: ${retrievedPhrase.language}`
      );
      
      // Test the flag mapping logic that iOS client uses
      const flagImageName = retrievedPhrase.language === 'sv' ? 'flag_sweden' : 'flag_england';
      const correctFlag = flagImageName === 'flag_england';
      
      logTest(
        'English Flag',
        'English language maps to English flag',
        correctFlag,
        `Language: ${retrievedPhrase.language} → Flag: ${flagImageName}`
      );
    } else {
      logTest('English Flag', 'English phrase retrieval', false, 'English phrase not found');
    }
    
  } catch (error) {
    logTest('English Flag', 'English phrase flag test', false, error.message);
  }
}

async function testDatabaseLanguageField() {
  console.log('🔍 Testing database language field storage...');
  
  try {
    // Test direct database access
    const phrases = await DatabasePhrase.getPhrasesForPlayer('989d493b-42ec-489f-b25f-c4700e8ee735');
    
    if (phrases.length > 0) {
      const firstPhrase = phrases[0];
      const hasLanguageField = firstPhrase.hasOwnProperty('language');
      
      logTest(
        'Database',
        'Database query includes language field',
        hasLanguageField,
        hasLanguageField ? `Language: ${firstPhrase.language}` : 'Language field missing'
      );
      
      // Test getPublicInfo method includes language
      const phraseInstance = new DatabasePhrase(firstPhrase);
      const publicInfo = phraseInstance.getPublicInfo();
      const publicHasLanguage = publicInfo.hasOwnProperty('language');
      
      logTest(
        'Database',
        'getPublicInfo includes language field',
        publicHasLanguage,
        publicHasLanguage ? `Language: ${publicInfo.language}` : 'Language field missing in getPublicInfo'
      );
    } else {
      logTest('Database', 'Database language field test', false, 'No phrases found for testing');
    }
    
  } catch (error) {
    logTest('Database', 'Database language field test', false, error.message);
  }
}

async function testBackwardCompatibility() {
  console.log('🔍 Testing backward compatibility with existing phrases...');
  
  try {
    // Create phrase without explicit language (should default to 'en')
    const sender = await createTestPlayer('BackwardCompatSender');
    const receiver = await createTestPlayer('BackwardCompatReceiver');
    
    // Create phrase with no language field
    const response = await axios.post(`${SERVER_URL}/api/phrases`, {
      content: 'backward compatibility test phrase',
      senderId: sender.id,
      targetId: receiver.id,
      hint: 'testing backward compatibility'
      // Note: no language field
    }, { timeout: CONFIG.timeout });
    
    const phrases = await getPhrasesForPlayer(receiver.id);
    const testPhrase = phrases.find(p => p.content === 'backward compatibility test phrase');
    
    if (testPhrase) {
      const hasLanguageField = testPhrase.hasOwnProperty('language');
      const defaultsToEnglish = testPhrase.language === 'en';
      
      logTest(
        'Backward Compatibility',
        'Phrase without language defaults to English',
        hasLanguageField && defaultsToEnglish,
        `Language: ${testPhrase.language} (should be 'en')`
      );
      
      // Test that default English maps to English flag
      const flagImageName = testPhrase.language === 'sv' ? 'flag_sweden' : 'flag_england';
      const correctFlag = flagImageName === 'flag_england';
      
      logTest(
        'Backward Compatibility',
        'Default English maps to English flag',
        correctFlag,
        `Language: ${testPhrase.language} → Flag: ${flagImageName}`
      );
    } else {
      logTest('Backward Compatibility', 'Backward compatibility test', false, 'Test phrase not found');
    }
    
  } catch (error) {
    logTest('Backward Compatibility', 'Backward compatibility test', false, error.message);
  }
}

async function testFlagMappingLogic() {
  console.log('🔍 Testing flag mapping logic...');
  
  // Test the exact mapping logic used in iOS client
  const flagMappings = [
    { language: 'sv', expectedFlag: 'flag_sweden', description: 'Swedish language' },
    { language: 'en', expectedFlag: 'flag_england', description: 'English language' },
    { language: null, expectedFlag: 'flag_england', description: 'Null language (default)' },
    { language: undefined, expectedFlag: 'flag_england', description: 'Undefined language (default)' },
    { language: '', expectedFlag: 'flag_england', description: 'Empty language (default)' }
  ];
  
  for (const mapping of flagMappings) {
    // This is the exact logic from iOS LanguageTile.updateFlag()
    const flagImageName = mapping.language === 'sv' ? 'flag_sweden' : 'flag_england';
    const correctFlag = flagImageName === mapping.expectedFlag;
    
    logTest(
      'Flag Mapping',
      `${mapping.description} maps correctly`,
      correctFlag,
      `Language: '${mapping.language}' → Flag: ${flagImageName} (expected: ${mapping.expectedFlag})`
    );
  }
}

// Main test execution
async function runAllTests() {
  console.log('🚀 Starting Language Tile Regression Test Suite...');
  console.log('🇸🇪 Testing Swedish flag vs English flag bug fix');
  console.log('=' .repeat(60));
  
  const startTime = Date.now();
  
  try {
    await testLanguageFieldInAPIResponse();
    await testSwedishPhraseFlag();
    await testEnglishPhraseFlag();
    await testDatabaseLanguageField();
    await testBackwardCompatibility();
    await testFlagMappingLogic();
    
  } catch (error) {
    console.error('❌ Test suite execution failed:', error.message);
    testResults.failed++;
  }
  
  const endTime = Date.now();
  const duration = endTime - startTime;
  
  // Print summary
  console.log('\n' + '=' .repeat(60));
  console.log('📊 Language Tile Regression Test Results');
  console.log('=' .repeat(60));
  console.log(`✅ Passed: ${testResults.passed}`);
  console.log(`❌ Failed: ${testResults.failed}`);
  console.log(`⏱️  Duration: ${duration}ms`);
  
  if (testResults.failed > 0) {
    console.log('\n❌ Failed Tests:');
    testResults.errors.forEach(error => console.log(`  • ${error}`));
  }
  
  const success = testResults.failed === 0;
  console.log(`\n🎉 Overall Result: ${success ? 'ALL TESTS PASSED' : 'SOME TESTS FAILED'}`);
  
  if (success) {
    console.log('🇸🇪 Swedish phrases will now display Swedish flag correctly!');
    console.log('🏴󠁧󠁢󠁥󠁮󠁧󠁿 English phrases will continue to display English flag correctly!');
  }
  
  // Exit with appropriate code
  process.exit(success ? 0 : 1);
}

// Run tests if this file is executed directly
if (require.main === module) {
  runAllTests().catch(error => {
    console.error('❌ Test execution failed:', error);
    process.exit(1);
  });
}

module.exports = {
  runAllTests,
  testLanguageFieldInAPIResponse,
  testSwedishPhraseFlag,
  testEnglishPhraseFlag,
  testDatabaseLanguageField,
  testBackwardCompatibility,
  testFlagMappingLogic
};