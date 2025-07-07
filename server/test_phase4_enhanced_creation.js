#!/usr/bin/env node

/**
 * Phase 4.1 Enhanced Phrase Creation Tests
 * 
 * Tests the new POST /api/phrases/create endpoint with comprehensive options:
 * - Multi-player targeting
 * - Global phrase creation
 * - Advanced hint validation
 * - Difficulty levels and phrase types
 * - Enhanced response format
 * 
 * Usage: node test_phase4_enhanced_creation.js
 */

const axios = require('axios');
const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

class Phase4EnhancedCreationTests {
  constructor() {
    this.results = {
      passed: 0,
      failed: 0,
      skipped: 0,
      details: []
    };
    this.testPlayers = [];
    this.testPhrases = [];
    this.sockets = [];
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = level === 'error' ? '❌' : level === 'success' ? '✅' : level === 'warn' ? '⚠️' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
  }

  logResult(testName, passed, details = '') {
    const status = passed ? '✅ PASS' : '❌ FAIL';
    console.log(`${status} [Phase4.1] ${testName}`);
    if (details) {
      console.log(`      ${details}`);
    }
    
    this.results.details.push({ testName, passed, details });
    if (passed) {
      this.results.passed++;
    } else {
      this.results.failed++;
    }
  }

  async makeRequest(method, url, data = null, expectedStatus = 200) {
    try {
      const config = {
        method,
        url: `${SERVER_URL}${url}`,
        timeout: 5000,
        headers: { 'Content-Type': 'application/json' }
      };

      if (data) config.data = data;
      const response = await axios(config);
      
      return {
        success: response.status === expectedStatus,
        status: response.status,
        data: response.data,
        error: null
      };
    } catch (error) {
      return {
        success: false,
        status: error.response?.status || 0,
        data: error.response?.data || null,
        error: error.message
      };
    }
  }

  // Test basic enhanced phrase creation
  async testBasicEnhancedCreation() {
    this.log('Testing basic enhanced phrase creation...');
    
    if (this.testPlayers.length < 2) {
      this.logResult('Basic enhanced creation', false, 'Need at least 2 players');
      return false;
    }

    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'hello world amazing test',
      hint: 'Testing the new enhanced endpoint',
      senderId: this.testPlayers[0].id,
      targetIds: [this.testPlayers[1].id],
      difficultyLevel: 2,
      phraseType: 'custom',
      priority: 1
    }, 201);

    const passed = result.success && 
      result.data.success &&
      result.data.phrase &&
      result.data.phrase.difficultyLevel === 2 &&
      result.data.phrase.phraseType === 'custom' &&
      result.data.phrase.priority === 1 &&
      result.data.phrase.senderInfo &&
      result.data.targeting;

    this.logResult('Basic enhanced creation',
      passed,
      passed ? `Created phrase with ID: ${result.data.phrase.id}` : `Error: ${result.error || result.data?.error}`);

    if (passed) {
      this.testPhrases.push(result.data.phrase);
    }

    return passed;
  }

  // Test global phrase creation
  async testGlobalPhraseCreation() {
    this.log('Testing global phrase creation...');
    
    if (this.testPlayers.length < 1) {
      this.logResult('Global phrase creation', false, 'Need at least 1 player');
      return false;
    }

    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'global test phrase for everyone',
      hint: 'Available to all participants',
      senderId: this.testPlayers[0].id,
      isGlobal: true,
      difficultyLevel: 3,
      phraseType: 'community',
      priority: 2
    }, 201);

    const passed = result.success && 
      result.data.success &&
      result.data.phrase &&
      result.data.phrase.isGlobal === true &&
      result.data.phrase.phraseType === 'community' &&
      result.data.targeting.isGlobal === true &&
      result.data.targeting.targetCount === 0;

    this.logResult('Global phrase creation',
      passed,
      passed ? `Global phrase created: ${result.data.phrase.id}` : `Error: ${result.error || result.data?.error}`);

    return passed;
  }

  // Test multi-player targeting
  async testMultiPlayerTargeting() {
    this.log('Testing multi-player targeting...');
    
    if (this.testPlayers.length < 3) {
      this.logResult('Multi-player targeting', false, 'Need at least 3 players');
      return false;
    }

    const targetIds = [this.testPlayers[1].id, this.testPlayers[2].id];
    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'multi target test phrase',
      hint: 'Challenge for multiple recipients',
      senderId: this.testPlayers[0].id,
      targetIds: targetIds,
      difficultyLevel: 4,
      phraseType: 'challenge',
      priority: 3
    }, 201);

    const passed = result.success && 
      result.data.success &&
      result.data.phrase &&
      result.data.targeting.targetCount === 2 &&
      result.data.phrase.phraseType === 'challenge';

    this.logResult('Multi-player targeting',
      passed,
      passed ? `Phrase sent to ${result.data.targeting.targetCount} players` : `Error: ${result.error || result.data?.error}`);

    return passed;
  }

  // Test hint validation
  async testHintValidation() {
    this.log('Testing hint validation...');
    
    if (this.testPlayers.length < 1) {
      this.logResult('Hint validation', false, 'Need at least 1 player');
      return false;
    }

    // Test 1: Hint too short
    const result1 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'validation test phrase',
      hint: 'Hi',
      senderId: this.testPlayers[0].id,
      isGlobal: true
    }, 400);

    const test1Passed = !result1.success && result1.status === 400;

    // Test 2: Hint contains exact words from phrase
    const result2 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'validation test phrase',
      hint: 'This hint contains the word validation from the phrase',
      senderId: this.testPlayers[0].id,
      isGlobal: true
    }, 400);

    const test2Passed = !result2.success && result2.status === 400;

    // Test 3: Valid hint
    const result3 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'validation test phrase',
      hint: 'Unscramble this challenging message',
      senderId: this.testPlayers[0].id,
      isGlobal: true
    }, 201);

    const test3Passed = result3.success && result3.data.success;

    const allPassed = test1Passed && test2Passed && test3Passed;

    this.logResult('Hint validation - too short',
      test1Passed,
      test1Passed ? 'Correctly rejected short hint' : 'Should have rejected short hint');

    this.logResult('Hint validation - contains phrase words',
      test2Passed,
      test2Passed ? 'Correctly rejected hint with phrase words' : 'Should have rejected hint with phrase words');

    this.logResult('Hint validation - valid hint',
      test3Passed,
      test3Passed ? 'Accepted valid hint' : 'Should have accepted valid hint');

    return allPassed;
  }

  // Test difficulty level validation
  async testDifficultyValidation() {
    this.log('Testing difficulty level validation...');
    
    if (this.testPlayers.length < 1) {
      this.logResult('Difficulty validation', false, 'Need at least 1 player');
      return false;
    }

    // Test invalid difficulty (too low)
    const result1 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'difficulty test phrase',
      hint: 'Testing difficulty boundaries',
      senderId: this.testPlayers[0].id,
      isGlobal: true,
      difficultyLevel: 0
    }, 400);

    const test1Passed = !result1.success && result1.status === 400;

    // Test invalid difficulty (too high)
    const result2 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'difficulty test phrase',
      hint: 'Testing difficulty boundaries',
      senderId: this.testPlayers[0].id,
      isGlobal: true,
      difficultyLevel: 6
    }, 400);

    const test2Passed = !result2.success && result2.status === 400;

    // Test valid difficulties (1-5)
    let validTests = 0;
    for (let difficulty = 1; difficulty <= 5; difficulty++) {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content: `level ${difficulty} sample words`,
        hint: `Unscramble this level ${difficulty} message`,
        senderId: this.testPlayers[0].id,
        isGlobal: true,
        difficultyLevel: difficulty
      }, 201);

      if (result.success && result.data.phrase.difficultyLevel === difficulty) {
        validTests++;
      }
    }

    const test3Passed = validTests === 5;

    this.logResult('Difficulty validation - too low',
      test1Passed,
      test1Passed ? 'Correctly rejected difficulty 0' : 'Should have rejected difficulty 0');

    this.logResult('Difficulty validation - too high',
      test2Passed,
      test2Passed ? 'Correctly rejected difficulty 6' : 'Should have rejected difficulty 6');

    this.logResult('Difficulty validation - valid range',
      test3Passed,
      test3Passed ? 'All difficulties 1-5 accepted' : `Only ${validTests}/5 valid difficulties accepted`);

    return test1Passed && test2Passed && test3Passed;
  }

  // Test phrase type validation
  async testPhraseTypeValidation() {
    this.log('Testing phrase type validation...');
    
    if (this.testPlayers.length < 1) {
      this.logResult('Phrase type validation', false, 'Need at least 1 player');
      return false;
    }

    // Test invalid phrase type
    const result1 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'phrase type test',
      hint: 'Testing phrase type boundaries',
      senderId: this.testPlayers[0].id,
      isGlobal: true,
      phraseType: 'invalid_type'
    }, 400);

    const test1Passed = !result1.success && result1.status === 400;

    // Test valid phrase types
    const validTypes = ['custom', 'global', 'community', 'challenge'];
    let validTests = 0;
    
    for (const phraseType of validTypes) {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content: `${phraseType} type test phrase`,
        hint: `Testing ${phraseType} phrase type`,
        senderId: this.testPlayers[0].id,
        isGlobal: true,
        phraseType: phraseType
      }, 201);

      if (result.success && result.data.phrase.phraseType === phraseType) {
        validTests++;
      }
    }

    const test2Passed = validTests === validTypes.length;

    this.logResult('Phrase type validation - invalid type',
      test1Passed,
      test1Passed ? 'Correctly rejected invalid phrase type' : 'Should have rejected invalid phrase type');

    this.logResult('Phrase type validation - valid types',
      test2Passed,
      test2Passed ? `All ${validTypes.length} valid types accepted` : `Only ${validTests}/${validTypes.length} valid types accepted`);

    return test1Passed && test2Passed;
  }

  // Test enhanced response format
  async testEnhancedResponseFormat() {
    this.log('Testing enhanced response format...');
    
    if (this.testPlayers.length < 2) {
      this.logResult('Enhanced response format', false, 'Need at least 2 players');
      return false;
    }

    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'sample output testing demo',
      hint: 'Check the enhanced data format',
      senderId: this.testPlayers[0].id,
      targetIds: [this.testPlayers[1].id],
      difficultyLevel: 3,
      phraseType: 'custom',
      priority: 2
    }, 201);


    const hasRequiredFields = result.success &&
      result.data.success &&
      result.data.phrase &&
      result.data.phrase.id &&
      result.data.phrase.content &&
      result.data.phrase.hint &&
      result.data.phrase.difficultyLevel &&
      result.data.phrase.phraseType &&
      result.data.phrase.priority &&
      result.data.phrase.senderInfo &&
      result.data.phrase.senderInfo.id &&
      result.data.phrase.senderInfo.name &&
      result.data.targeting &&
      typeof result.data.targeting.isGlobal === 'boolean' &&
      typeof result.data.targeting.targetCount === 'number' &&
      typeof result.data.targeting.notificationsSent === 'number' &&
      result.data.message;

    this.logResult('Enhanced response format',
      hasRequiredFields,
      hasRequiredFields ? 'All required fields present in response' : 'Missing required fields in response');

    return hasRequiredFields;
  }

  // Test error handling
  async testErrorHandling() {
    this.log('Testing error handling...');
    
    // Test missing content
    const result1 = await this.makeRequest('POST', '/api/phrases/create', {
      hint: 'Missing content field',
      senderId: 'test-id'
    }, 400);

    const test1Passed = !result1.success && result1.status === 400;

    // Test missing senderId
    const result2 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'missing sender test',
      hint: 'Missing sender field'
    }, 400);

    const test2Passed = !result2.success && result2.status === 400;

    // Test invalid senderId
    const result3 = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'invalid sender test',
      hint: 'Invalid sender field',
      senderId: 'nonexistent-player-id'
    }, 404);

    const test3Passed = !result3.success && result3.status === 404;

    this.logResult('Error handling - missing content',
      test1Passed,
      test1Passed ? 'Correctly rejected missing content' : 'Should have rejected missing content');

    this.logResult('Error handling - missing senderId',
      test2Passed,
      test2Passed ? 'Correctly rejected missing senderId' : 'Should have rejected missing senderId');

    this.logResult('Error handling - invalid senderId',
      test3Passed,
      test3Passed ? 'Correctly rejected invalid senderId' : 'Should have rejected invalid senderId');

    return test1Passed && test2Passed && test3Passed;
  }

  // Setup test players
  async setupTestPlayers() {
    this.log('Setting up test players for Phase 4.1 tests...');

    // First, try to get existing test players
    const existingResult = await this.makeRequest('GET', '/api/players/online');
    if (existingResult.success && existingResult.data.players.length >= 3) {
      this.testPlayers = existingResult.data.players.slice(0, 3);
      this.logResult('Test player setup',
        true,
        `Using ${this.testPlayers.length} existing players for tests`);
      return true;
    }

    // Create new players with unique names
    const timestamp = Date.now();
    const playerNames = [
      `Phase41User1_${timestamp}`, 
      `Phase41User2_${timestamp}`, 
      `Phase41User3_${timestamp}`
    ];
    
    for (const name of playerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        socketId: `phase41-test-${Date.now()}-${Math.random()}`
      });

      if (result.success) {
        this.testPlayers.push(result.data.player);
      } else {
        this.log(`Failed to create player ${name}: ${result.error}`, 'warn');
      }
    }

    const setupSuccess = this.testPlayers.length >= 3;
    this.logResult('Test player setup',
      setupSuccess,
      setupSuccess ? 
        `${this.testPlayers.length} test players ready` : 
        `Only ${this.testPlayers.length} players available - need at least 3`);

    return setupSuccess;
  }

  // Run all Phase 4.1 tests
  async runAllTests() {
    this.log('🧪 Starting Phase 4.1 Enhanced Creation Tests...\n');
    
    // Setup
    const setupSuccess = await this.setupTestPlayers();
    if (!setupSuccess) {
      this.log('❌ Test setup failed - aborting Phase 4.1 tests');
      return false;
    }

    const testSuites = [
      { name: 'Basic Enhanced Creation', test: () => this.testBasicEnhancedCreation() },
      { name: 'Global Phrase Creation', test: () => this.testGlobalPhraseCreation() },
      { name: 'Multi-Player Targeting', test: () => this.testMultiPlayerTargeting() },
      { name: 'Hint Validation', test: () => this.testHintValidation() },
      { name: 'Difficulty Validation', test: () => this.testDifficultyValidation() },
      { name: 'Phrase Type Validation', test: () => this.testPhraseTypeValidation() },
      { name: 'Enhanced Response Format', test: () => this.testEnhancedResponseFormat() },
      { name: 'Error Handling', test: () => this.testErrorHandling() }
    ];

    const results = [];
    
    for (const suite of testSuites) {
      this.log(`\n🔍 Running ${suite.name} tests...`);
      try {
        const result = await suite.test();
        results.push({ name: suite.name, passed: result });
        this.log(`${result ? '✅' : '❌'} ${suite.name} tests ${result ? 'passed' : 'failed'}`);
      } catch (error) {
        this.log(`❌ ${suite.name} tests failed with error: ${error.message}`, 'error');
        results.push({ name: suite.name, passed: false, error: error.message });
      }
    }

    // Summary
    this.log('\n📊 Phase 4.1 Enhanced Creation Test Summary:');
    this.log(`✅ Passed: ${this.results.passed}`);
    this.log(`❌ Failed: ${this.results.failed}`);
    this.log(`⏭️ Skipped: ${this.results.skipped}`);
    this.log(`🎯 Total: ${this.results.passed + this.results.failed + this.results.skipped}`);

    this.log('\n📋 Test Suite Results:');
    results.forEach(result => {
      const status = result.passed ? '✅' : '❌';
      this.log(`${status} ${result.name}${result.error ? ` (${result.error})` : ''}`);
    });

    const overallPassed = this.results.failed === 0;
    this.log(`\n🎉 Phase 4.1 Enhanced Creation Tests: ${overallPassed ? 'ALL PASSED' : 'SOME FAILED'}`);
    
    return overallPassed;
  }

  // Cleanup
  async cleanup() {
    this.sockets.forEach(socket => {
      if (socket && socket.connected) {
        socket.disconnect();
      }
    });
    this.log('🧹 Phase 4.1 test cleanup completed');
  }
}

// Run tests if script is executed directly
if (require.main === module) {
  const testSuite = new Phase4EnhancedCreationTests();
  
  testSuite.runAllTests()
    .then(async (success) => {
      await testSuite.cleanup();
      process.exit(success ? 0 : 1);
    })
    .catch(async (error) => {
      console.error('❌ Phase 4.1 enhanced creation tests execution failed:', error);
      await testSuite.cleanup();
      process.exit(1);
    });
}

module.exports = Phase4EnhancedCreationTests;