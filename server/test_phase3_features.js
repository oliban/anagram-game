#!/usr/bin/env node

/**
 * Phase 3 Feature Tests - Hint System and Database Integration
 * 
 * Tests specific Phase 3 features that weren't covered in basic API tests:
 * - Hint generation and inclusion in responses
 * - Database persistence across operations
 * - Player targeting and phrase queuing
 * - WebSocket hint delivery
 * - Database-specific validation
 * 
 * Usage: node test_phase3_features.js
 */

const axios = require('axios');
const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

class Phase3FeatureTests {
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
    console.log(`${status} [Phase3] ${testName}`);
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

  // Test automatic hint generation
  async testHintGeneration() {
    this.log('Testing automatic hint generation...');
    
    if (this.testPlayers.length < 2) {
      this.logResult('Hint generation', false, 'Need at least 2 players');
      return false;
    }

    // Test 1: Create phrase without hint - should auto-generate
    const result1 = await this.makeRequest('POST', '/api/phrases', {
      content: 'hello world test',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id
    }, 201);

    const hasAutoHint = result1.success && 
      result1.data.phrase.hint && 
      result1.data.phrase.hint.includes('word');

    this.logResult('Automatic hint generation',
      hasAutoHint,
      hasAutoHint ? `Generated hint: "${result1.data.phrase.hint}"` : 'No hint generated');

    // Test 2: Create phrase with custom hint
    const result2 = await this.makeRequest('POST', '/api/phrases', {
      content: 'quick brown fox',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'Famous typing test animal'
    }, 201);

    const hasCustomHint = result2.success && 
      result2.data.phrase.hint === 'Famous typing test animal';

    this.logResult('Custom hint preservation',
      hasCustomHint,
      hasCustomHint ? `Custom hint preserved: "${result2.data.phrase.hint}"` : 'Custom hint not preserved');

    if (result1.success) this.testPhrases.push(result1.data.phrase);
    if (result2.success) this.testPhrases.push(result2.data.phrase);

    return hasAutoHint && hasCustomHint;
  }

  // Test phrase response includes hint data
  async testHintInResponses() {
    this.log('Testing hint inclusion in API responses...');

    if (this.testPlayers.length < 2) {
      this.logResult('Hint in responses', false, 'Need at least 2 players');
      return false;
    }

    // Create a test phrase first to ensure we have data to test
    await this.makeRequest('POST', '/api/phrases', {
      content: 'hint response test',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'Test hint for response validation'
    }, 201);

    // Test phrase retrieval includes hints (use player 1 who receives phrases)
    const result = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
    
    const hasHintsInResponse = result.success && 
      result.data.phrases && 
      result.data.phrases.length > 0 &&
      result.data.phrases.every(phrase => phrase.hint);

    // Debug logging to see what's actually returned
    if (result.success && result.data.phrases && result.data.phrases.length > 0) {
      console.log('      DEBUG: First phrase structure:', JSON.stringify(result.data.phrases[0], null, 2));
    }

    this.logResult('Hints in phrase retrieval',
      hasHintsInResponse,
      hasHintsInResponse ? 
        `All ${result.data.phrases.length} phrases include hints` : 
        'Some phrases missing hints');

    // Test hint structure
    if (hasHintsInResponse) {
      const firstPhrase = result.data.phrases[0];
      const hasValidStructure = firstPhrase.id && 
        firstPhrase.content && 
        firstPhrase.hint &&
        typeof firstPhrase.hint === 'string';

      this.logResult('Phrase response structure with hints',
        hasValidStructure,
        hasValidStructure ? 'Valid structure with hint field' : 'Invalid phrase structure');

      return hasValidStructure;
    }

    return hasHintsInResponse;
  }

  // Test database persistence
  async testDatabasePersistence() {
    this.log('Testing database persistence...');

    // Create a phrase and verify it persists
    if (this.testPlayers.length < 2) {
      this.logResult('Database persistence', false, 'Need at least 2 players');
      return false;
    }

    const createResult = await this.makeRequest('POST', '/api/phrases', {
      content: 'persistence test phrase',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'Testing database storage'
    }, 201);

    if (!createResult.success) {
      this.logResult('Database persistence - create', false, 'Failed to create test phrase');
      return false;
    }

    const phraseId = createResult.data.phrase.id;

    // Retrieve phrase and verify data matches
    const retrieveResult = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
    
    const persistedPhrase = retrieveResult.success && 
      retrieveResult.data.phrases.find(p => p.id === phraseId);

    const dataMatches = persistedPhrase &&
      persistedPhrase.content === 'persistence test phrase' &&
      persistedPhrase.hint === 'Testing database storage' &&
      persistedPhrase.senderId === this.testPlayers[0].id &&
      persistedPhrase.targetId === this.testPlayers[1].id;

    this.logResult('Database persistence - data integrity',
      dataMatches,
      dataMatches ? 'All phrase data persisted correctly' : 'Data mismatch in persistence');

    return dataMatches;
  }

  // Test player targeting system
  async testPlayerTargeting() {
    this.log('Testing player targeting system...');

    if (this.testPlayers.length < 3) {
      this.logResult('Player targeting', false, 'Need at least 3 players for targeting test');
      return false;
    }

    // Create targeted phrase from player 0 to player 1
    const targetResult = await this.makeRequest('POST', '/api/phrases', {
      content: 'targeted test phrase',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'This phrase is targeted'
    }, 201);

    if (!targetResult.success) {
      this.logResult('Player targeting - create', false, 'Failed to create targeted phrase');
      return false;
    }

    // Verify phrase appears for target player (player 1)
    const targetPhrases = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
    const hasTargetedPhrase = targetPhrases.success &&
      targetPhrases.data.phrases.some(p => p.content === 'targeted test phrase');

    this.logResult('Player targeting - target receives',
      hasTargetedPhrase,
      hasTargetedPhrase ? 'Targeted player received phrase' : 'Targeted player did not receive phrase');

    // Verify phrase does NOT appear for other player (player 2)
    const otherPhrases = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[2].id}`);
    const doesNotHavePhrase = otherPhrases.success &&
      !otherPhrases.data.phrases.some(p => p.content === 'targeted test phrase');

    this.logResult('Player targeting - others do not receive',
      doesNotHavePhrase,
      doesNotHavePhrase ? 'Non-targeted player correctly excluded' : 'Non-targeted player received phrase');

    return hasTargetedPhrase && doesNotHavePhrase;
  }

  // Test WebSocket hint delivery
  async testWebSocketHints() {
    this.log('Testing WebSocket hint delivery...');

    return new Promise((resolve) => {
      if (this.testPlayers.length < 2) {
        this.logResult('WebSocket hints', false, 'Need at least 2 players');
        resolve(false);
        return;
      }

      let hintReceived = false;
      let hintData = null;

      // Create socket connection for target player
      const socket = io(WS_URL, { transports: ['websocket'] });
      this.sockets.push(socket);

      socket.on('connect', async () => {
        // Simulate player connection
        socket.emit('player-connect', { playerId: this.testPlayers[1].id });

        // Set up listener for new-phrase event
        socket.on('new-phrase', (data) => {
          hintReceived = true;
          hintData = data;
          
          const hasHint = data.phrase && data.phrase.hint;
          const hasValidStructure = data.senderName && data.timestamp && data.phrase.content;
          
          this.logResult('WebSocket hint delivery',
            hasHint && hasValidStructure,
            hasHint ? 
              `Received hint: "${data.phrase.hint}" from ${data.senderName}` : 
              'No hint in WebSocket event');

          socket.disconnect();
          resolve(hasHint && hasValidStructure);
        });

        // Create phrase after short delay to ensure socket is ready
        setTimeout(async () => {
          await this.makeRequest('POST', '/api/phrases', {
            content: 'websocket hint test',
            senderId: this.testPlayers[0].id,
            targetId: this.testPlayers[1].id,
            hint: 'WebSocket test hint message'
          }, 201);
        }, 1000);
      });

      // Timeout fallback
      setTimeout(() => {
        if (!hintReceived) {
          this.logResult('WebSocket hint delivery', false, 'Timeout - no WebSocket event received');
          socket.disconnect();
          resolve(false);
        }
      }, 8000);
    });
  }

  // Test phrase consumption and delivery tracking
  async testPhraseLifecycle() {
    this.log('Testing phrase lifecycle (create → deliver → consume)...');

    if (this.testPlayers.length < 2) {
      this.logResult('Phrase lifecycle', false, 'Need at least 2 players');
      return false;
    }

    // Create phrase
    const createResult = await this.makeRequest('POST', '/api/phrases', {
      content: 'lifecycle test phrase',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'Testing full phrase lifecycle'
    }, 201);

    if (!createResult.success) {
      this.logResult('Phrase lifecycle - create', false, 'Failed to create phrase');
      return false;
    }

    const phraseId = createResult.data.phrase.id;

    // Verify phrase is available
    const beforeConsume = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
    const isAvailable = beforeConsume.success &&
      beforeConsume.data.phrases.some(p => p.id === phraseId);

    this.logResult('Phrase lifecycle - available before consume',
      isAvailable,
      isAvailable ? 'Phrase available for consumption' : 'Phrase not available');

    // Consume phrase
    const consumeResult = await this.makeRequest('POST', `/api/phrases/${phraseId}/consume`, {}, 200);
    const consumeSuccess = consumeResult.success && consumeResult.data.success;

    this.logResult('Phrase lifecycle - consumption',
      consumeSuccess,
      consumeSuccess ? 'Phrase consumed successfully' : 'Failed to consume phrase');

    // Verify phrase is no longer available
    const afterConsume = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
    const isNoLongerAvailable = afterConsume.success &&
      !afterConsume.data.phrases.some(p => p.id === phraseId);

    this.logResult('Phrase lifecycle - unavailable after consume',
      isNoLongerAvailable,
      isNoLongerAvailable ? 'Phrase correctly removed after consumption' : 'Phrase still available after consumption');

    return isAvailable && consumeSuccess && isNoLongerAvailable;
  }

  // Setup test players
  async setupTestPlayers() {
    this.log('Setting up test players for Phase 3 tests...');

    // First, try to get existing test players
    const existingResult = await this.makeRequest('GET', '/api/players/online');
    if (existingResult.success && existingResult.data.players.length >= 2) {
      this.testPlayers = existingResult.data.players.slice(0, 3);
      this.logResult('Test player setup',
        true,
        `Using ${this.testPlayers.length} existing players for tests`);
      return true;
    }

    // Create new players with unique names
    const timestamp = Date.now();
    const playerNames = [
      `Phase3User1_${timestamp}`, 
      `Phase3User2_${timestamp}`, 
      `Phase3User3_${timestamp}`
    ];
    
    for (const name of playerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        socketId: `phase3-test-${Date.now()}-${Math.random()}`
      });

      if (result.success) {
        this.testPlayers.push(result.data.player);
      } else {
        this.log(`Failed to create player ${name}: ${result.error}`, 'warn');
      }
    }

    const setupSuccess = this.testPlayers.length >= 2;
    this.logResult('Test player setup',
      setupSuccess,
      setupSuccess ? 
        `${this.testPlayers.length} test players ready` : 
        `Only ${this.testPlayers.length} players available - need at least 2`);

    return setupSuccess;
  }

  // Run all Phase 3 tests
  async runAllTests() {
    this.log('🧪 Starting Phase 3 Feature Tests...\n');
    
    // Setup
    const setupSuccess = await this.setupTestPlayers();
    if (!setupSuccess) {
      this.log('❌ Test setup failed - aborting Phase 3 tests');
      return false;
    }

    const testSuites = [
      { name: 'Hint Generation', test: () => this.testHintGeneration() },
      { name: 'Hint in Responses', test: () => this.testHintInResponses() },
      { name: 'Database Persistence', test: () => this.testDatabasePersistence() },
      { name: 'Player Targeting', test: () => this.testPlayerTargeting() },
      { name: 'WebSocket Hints', test: () => this.testWebSocketHints() },
      { name: 'Phrase Lifecycle', test: () => this.testPhraseLifecycle() }
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
    this.log('\n📊 Phase 3 Feature Test Summary:');
    this.log(`✅ Passed: ${this.results.passed}`);
    this.log(`❌ Failed: ${this.results.failed}`);
    this.log(`⏭️ Skipped: ${this.results.skipped}`);
    this.log(`🎯 Total: ${this.results.passed + this.results.failed + this.results.skipped}`);

    this.log('\n📋 Feature Test Results:');
    results.forEach(result => {
      const status = result.passed ? '✅' : '❌';
      this.log(`${status} ${result.name}${result.error ? ` (${result.error})` : ''}`);
    });

    const overallPassed = this.results.failed === 0;
    this.log(`\n🎉 Phase 3 Feature Tests: ${overallPassed ? 'ALL PASSED' : 'SOME FAILED'}`);
    
    return overallPassed;
  }

  // Cleanup
  async cleanup() {
    this.sockets.forEach(socket => {
      if (socket && socket.connected) {
        socket.disconnect();
      }
    });
    this.log('🧹 Phase 3 test cleanup completed');
  }
}

// Run tests if script is executed directly
if (require.main === module) {
  const testSuite = new Phase3FeatureTests();
  
  testSuite.runAllTests()
    .then(async (success) => {
      await testSuite.cleanup();
      process.exit(success ? 0 : 1);
    })
    .catch(async (error) => {
      console.error('❌ Phase 3 feature tests execution failed:', error);
      await testSuite.cleanup();
      process.exit(1);
    });
}

module.exports = Phase3FeatureTests;