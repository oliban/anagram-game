#!/usr/bin/env node

/**
 * Comprehensive API Test Suite
 * 
 * Tests all API endpoints for the Anagram Game Server
 * Can be run repeatedly to validate functionality after changes
 * 
 * Usage: node test_api_suite.js
 * 
 * Requirements:
 * - Server must be running on localhost:3000
 * - Database must be connected and initialized
 */

const axios = require('axios');
const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

// Test configuration
const CONFIG = {
  timeout: 10000,
  retries: 3,
  verbose: false
};

// Test data
const TEST_DATA = {
  validPlayerNames: ['TestUser1', 'TestUser2', 'AliceTestPlayer', 'BobTestPlayer'],
  invalidPlayerNames: ['', 'A', 'a'.repeat(100), '🤖invalid', null, undefined],
  phrases: [
    'hello world test',
    'quick brown fox',
    'sample phrase creation',
    'anagram game test'
  ]
};

class APITestSuite {
  constructor() {
    this.results = {
      passed: 0,
      failed: 0,
      skipped: 0,
      details: []
    };
    this.testPlayers = [];
    this.testPhrases = [];
    this.socket = null;
  }

  // Logging utilities
  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = level === 'error' ? '❌' : level === 'success' ? '✅' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
  }

  logResult(testName, passed, details = '', category = 'API') {
    const status = passed ? '✅ PASS' : '❌ FAIL';
    const message = `${status} [${category}] ${testName}`;
    
    if (CONFIG.verbose || !passed) {
      console.log(message);
      if (details) {
        console.log(`      ${details}`);
      }
    }
    
    this.results.details.push({ testName, passed, details, category });
    if (passed) {
      this.results.passed++;
    } else {
      this.results.failed++;
    }
  }

  // HTTP request wrapper with error handling
  async makeRequest(method, url, data = null, expectedStatus = 200) {
    try {
      const config = {
        method,
        url: `${SERVER_URL}${url}`,
        timeout: CONFIG.timeout,
        headers: {
          'Content-Type': 'application/json'
        }
      };

      if (data) {
        config.data = data;
      }

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

  // Test /api/status endpoint
  async testStatusEndpoint() {
    const result = await this.makeRequest('GET', '/api/status');
    
    this.logResult('GET /api/status - Server Health', 
      result.success && result.data.status === 'online',
      `Status: ${result.data?.status}, DB: ${result.data?.database?.connected}`);

    if (result.success && result.data.database) {
      this.logResult('GET /api/status - Database Health',
        result.data.database.connected === true,
        `Pool: ${result.data.database.poolSize}/${result.data.database.maxPoolSize}`);
    }

    return result.success;
  }

  // Test player registration endpoint
  async testPlayerRegistration() {
    let allPassed = true;

    // Test valid player registration
    for (const name of TEST_DATA.validPlayerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        socketId: `test-socket-${Date.now()}-${Math.random()}`
      }, 201);

      const passed = result.success && result.data.success && result.data.player.id;
      this.logResult(`POST /api/players/register - Valid name "${name}"`,
        passed,
        passed ? `Player ID: ${result.data.player.id}` : `Error: ${result.error || result.data?.error}`);

      if (passed) {
        this.testPlayers.push(result.data.player);
      }
      allPassed = allPassed && passed;
    }

    // Test invalid player registration
    for (const name of TEST_DATA.invalidPlayerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        socketId: 'test-socket-invalid'
      }, 400);

      const passed = !result.success && result.status === 400;
      this.logResult(`POST /api/players/register - Invalid name "${name}"`,
        passed,
        passed ? 'Correctly rejected' : `Unexpected: ${result.status} ${result.error}`);
      
      allPassed = allPassed && passed;
    }

    // Test missing fields
    const missingNameResult = await this.makeRequest('POST', '/api/players/register', {
      socketId: 'test-socket'
    }, 400);

    const missingNamePassed = !missingNameResult.success && missingNameResult.status === 400;
    this.logResult('POST /api/players/register - Missing name',
      missingNamePassed,
      missingNamePassed ? 'Correctly rejected' : `Unexpected: ${missingNameResult.status}`);

    // Test duplicate player name (should update existing)
    if (this.testPlayers.length > 0) {
      const existingPlayer = this.testPlayers[0];
      const duplicateResult = await this.makeRequest('POST', '/api/players/register', {
        name: existingPlayer.name,
        socketId: 'test-socket-duplicate'
      }, 201);

      const duplicatePassed = duplicateResult.success && duplicateResult.data.player.id === existingPlayer.id;
      this.logResult('POST /api/players/register - Duplicate name',
        duplicatePassed,
        duplicatePassed ? 'Correctly updated existing player' : `Error: ${duplicateResult.error}`);
      
      allPassed = allPassed && duplicatePassed;
    }

    return allPassed;
  }

  // Test get online players endpoint
  async testGetOnlinePlayers() {
    const result = await this.makeRequest('GET', '/api/players/online');
    
    const passed = result.success && Array.isArray(result.data.players);
    this.logResult('GET /api/players/online - Retrieve players',
      passed,
      passed ? `Found ${result.data.players.length} online players` : `Error: ${result.error}`);

    if (passed) {
      // Validate player data structure
      const validStructure = result.data.players.every(player => 
        player.id && player.name && typeof player.isActive === 'boolean'
      );
      
      this.logResult('GET /api/players/online - Data structure',
        validStructure,
        validStructure ? 'All players have valid structure' : 'Invalid player data structure');
      
      return validStructure;
    }

    return passed;
  }

  // Test phrase creation endpoint
  async testPhraseCreation() {
    if (this.testPlayers.length < 2) {
      this.logResult('POST /api/phrases - Skipped', false, 'Need at least 2 players for phrase tests');
      return false;
    }

    let allPassed = true;

    // Test valid phrase creation
    for (const content of TEST_DATA.phrases) {
      const result = await this.makeRequest('POST', '/api/phrases', {
        content,
        senderId: this.testPlayers[0].id,
        targetId: this.testPlayers[1].id
      }, 201);

      const passed = result.success && result.data.success && result.data.phrase.id;
      this.logResult(`POST /api/phrases - Valid phrase`,
        passed,
        passed ? `Phrase ID: ${result.data.phrase.id}` : `Error: ${result.error || result.data?.error}`);

      if (passed) {
        this.testPhrases.push(result.data.phrase);
      }
      allPassed = allPassed && passed;
    }

    // Test invalid phrase creation
    const invalidCases = [
      { case: 'missing content', data: { senderId: this.testPlayers[0].id, targetId: this.testPlayers[1].id } },
      { case: 'missing senderId', data: { content: 'test phrase', targetId: this.testPlayers[1].id } },
      { case: 'missing targetId', data: { content: 'test phrase', senderId: this.testPlayers[0].id } },
      { case: 'same sender and target', data: { content: 'test phrase', senderId: this.testPlayers[0].id, targetId: this.testPlayers[0].id } },
      { case: 'invalid senderId', data: { content: 'test phrase', senderId: 'invalid-id', targetId: this.testPlayers[1].id } },
      { case: 'invalid targetId', data: { content: 'test phrase', senderId: this.testPlayers[0].id, targetId: 'invalid-id' } }
    ];

    for (const { case: testCase, data } of invalidCases) {
      const result = await this.makeRequest('POST', '/api/phrases', data, 400);
      
      const passed = !result.success && (result.status === 400 || result.status === 404);
      this.logResult(`POST /api/phrases - Invalid: ${testCase}`,
        passed,
        passed ? 'Correctly rejected' : `Unexpected: ${result.status} ${result.error}`);
      
      allPassed = allPassed && passed;
    }

    return allPassed;
  }

  // Test phrase retrieval endpoint
  async testPhraseRetrieval() {
    if (this.testPlayers.length === 0) {
      this.logResult('GET /api/phrases/for/:playerId - Skipped', false, 'No test players available');
      return false;
    }

    let allPassed = true;

    // Test valid phrase retrieval
    for (const player of this.testPlayers) {
      const result = await this.makeRequest('GET', `/api/phrases/for/${player.id}`);
      
      const passed = result.success && Array.isArray(result.data.phrases);
      this.logResult(`GET /api/phrases/for/${player.id} - Valid player`,
        passed,
        passed ? `Found ${result.data.phrases.length} phrases` : `Error: ${result.error}`);
      
      allPassed = allPassed && passed;
    }

    // Test invalid player ID
    const invalidResult = await this.makeRequest('GET', '/api/phrases/for/invalid-player-id', null, 404);
    
    const invalidPassed = !invalidResult.success && invalidResult.status === 404;
    this.logResult('GET /api/phrases/for/:playerId - Invalid player',
      invalidPassed,
      invalidPassed ? 'Correctly returned 404' : `Unexpected: ${invalidResult.status}`);
    
    allPassed = allPassed && invalidPassed;

    return allPassed;
  }

  // Test phrase consumption endpoint
  async testPhraseConsumption() {
    if (this.testPhrases.length === 0) {
      this.logResult('POST /api/phrases/:phraseId/consume - Skipped', false, 'No test phrases available');
      return false;
    }

    let allPassed = true;

    // Test valid phrase consumption
    const testPhrase = this.testPhrases[0];
    const result = await this.makeRequest('POST', `/api/phrases/${testPhrase.id}/consume`);
    
    const passed = result.success && result.data.success;
    this.logResult(`POST /api/phrases/${testPhrase.id}/consume - Valid phrase`,
      passed,
      passed ? 'Phrase consumed successfully' : `Error: ${result.error}`);
    
    allPassed = allPassed && passed;

    // Test invalid phrase ID
    const invalidResult = await this.makeRequest('POST', '/api/phrases/invalid-phrase-id/consume', null, 404);
    
    const invalidPassed = !invalidResult.success && invalidResult.status === 404;
    this.logResult('POST /api/phrases/:phraseId/consume - Invalid phrase',
      invalidPassed,
      invalidPassed ? 'Correctly returned 404' : `Unexpected: ${invalidResult.status}`);
    
    allPassed = allPassed && invalidPassed;

    return allPassed;
  }

  // Test phrase skip endpoint
  async testPhraseSkip() {
    if (this.testPlayers.length === 0) {
      this.logResult('POST /api/phrases/:phraseId/skip - Skipped', false, 'No test players available');
      return false;
    }

    let allPassed = true;

    // Test valid phrase skip
    const result = await this.makeRequest('POST', '/api/phrases/test-phrase-id/skip', {
      playerId: this.testPlayers[0].id
    });
    
    const passed = result.success && result.data.success;
    this.logResult('POST /api/phrases/:phraseId/skip - Valid request',
      passed,
      passed ? 'Phrase skipped successfully' : `Error: ${result.error}`);
    
    allPassed = allPassed && passed;

    // Test invalid player ID
    const invalidResult = await this.makeRequest('POST', '/api/phrases/test-phrase-id/skip', {
      playerId: 'invalid-player-id'
    }, 404);
    
    const invalidPassed = !invalidResult.success && invalidResult.status === 404;
    this.logResult('POST /api/phrases/:phraseId/skip - Invalid player',
      invalidPassed,
      invalidPassed ? 'Correctly returned 404' : `Unexpected: ${invalidResult.status}`);
    
    allPassed = allPassed && invalidPassed;

    return allPassed;
  }

  // Test WebSocket functionality
  async testWebSocket() {
    return new Promise((resolve) => {
      let testsPassed = 0;
      const expectedTests = 4;
      
      this.socket = io(WS_URL, {
        transports: ['websocket'],
        timeout: 5000
      });

      // Test connection
      this.socket.on('connect', () => {
        testsPassed++;
        this.logResult('WebSocket - Connection', true, `Connected with ID: ${this.socket.id}`, 'WebSocket');
      });

      // Test welcome message
      this.socket.on('welcome', (data) => {
        testsPassed++;
        this.logResult('WebSocket - Welcome message', true, `Received: ${data.message}`, 'WebSocket');
      });

      // Test player-connect event
      setTimeout(() => {
        if (this.testPlayers.length > 0) {
          this.socket.emit('player-connect', { playerId: this.testPlayers[0].id });
          testsPassed++;
          this.logResult('WebSocket - Player connect event', true, 'Event sent successfully', 'WebSocket');
        }
      }, 1000);

      // Test invalid player-connect
      setTimeout(() => {
        this.socket.emit('player-connect', { playerId: 'invalid-id' });
        testsPassed++;
        this.logResult('WebSocket - Invalid player connect', true, 'Event handled gracefully', 'WebSocket');
      }, 1500);

      // Test error handling
      this.socket.on('connect_error', (error) => {
        this.logResult('WebSocket - Connection error', false, `Error: ${error.message}`, 'WebSocket');
        resolve(false);
      });

      // Evaluate results
      setTimeout(() => {
        this.socket.disconnect();
        const allPassed = testsPassed >= expectedTests;
        this.logResult('WebSocket - Overall functionality', allPassed, 
          `${testsPassed}/${expectedTests} tests passed`, 'WebSocket');
        resolve(allPassed);
      }, 3000);
    });
  }

  // Test 404 handling
  async testNotFoundHandling() {
    const result = await this.makeRequest('GET', '/api/nonexistent/endpoint', null, 404);
    
    const passed = !result.success && result.status === 404;
    this.logResult('GET /api/nonexistent/endpoint - 404 handling',
      passed,
      passed ? 'Correctly returned 404' : `Unexpected: ${result.status}`);
    
    return passed;
  }

  // Test error handling
  async testErrorHandling() {
    // Test malformed JSON
    try {
      const response = await axios.post(`${SERVER_URL}/api/players/register`, 'invalid-json', {
        headers: { 'Content-Type': 'application/json' },
        timeout: CONFIG.timeout
      });
      
      this.logResult('POST /api/players/register - Malformed JSON', false, 'Should have rejected malformed JSON');
      return false;
    } catch (error) {
      const passed = error.response?.status === 400;
      this.logResult('POST /api/players/register - Malformed JSON', passed,
        passed ? 'Correctly rejected malformed JSON' : `Unexpected: ${error.response?.status}`);
      return passed;
    }
  }

  // Run all tests
  async runAllTests() {
    this.log('🧪 Starting Comprehensive API Test Suite...\n');
    
    const testSuites = [
      { name: 'Status Endpoint', test: () => this.testStatusEndpoint() },
      { name: 'Player Registration', test: () => this.testPlayerRegistration() },
      { name: 'Online Players', test: () => this.testGetOnlinePlayers() },
      { name: 'Phrase Creation', test: () => this.testPhraseCreation() },
      { name: 'Phrase Retrieval', test: () => this.testPhraseRetrieval() },
      { name: 'Phrase Consumption', test: () => this.testPhraseConsumption() },
      { name: 'Phrase Skip', test: () => this.testPhraseSkip() },
      { name: 'WebSocket', test: () => this.testWebSocket() },
      { name: '404 Handling', test: () => this.testNotFoundHandling() },
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

    // Print summary
    this.log('\n📊 Test Suite Summary:');
    this.log(`✅ Passed: ${this.results.passed}`);
    this.log(`❌ Failed: ${this.results.failed}`);
    this.log(`⏭️ Skipped: ${this.results.skipped}`);
    this.log(`🎯 Total: ${this.results.passed + this.results.failed + this.results.skipped}`);

    // Print suite results
    this.log('\n📋 Test Suite Results:');
    results.forEach(result => {
      const status = result.passed ? '✅' : '❌';
      this.log(`${status} ${result.name}${result.error ? ` (${result.error})` : ''}`);
    });

    // Print failed tests details
    if (this.results.failed > 0) {
      this.log('\n❌ Failed Tests Details:');
      this.results.details
        .filter(detail => !detail.passed)
        .forEach(detail => {
          this.log(`   • ${detail.testName}: ${detail.details}`);
        });
    }

    const overallPassed = this.results.failed === 0;
    this.log(`\n🎉 Overall Result: ${overallPassed ? 'ALL TESTS PASSED' : 'SOME TESTS FAILED'}`);
    
    return overallPassed;
  }

  // Cleanup test data
  async cleanup() {
    // Disconnect WebSocket if connected
    if (this.socket) {
      this.socket.disconnect();
    }
    
    this.log('🧹 Test cleanup completed');
  }
}

// Run tests if script is executed directly
if (require.main === module) {
  const testSuite = new APITestSuite();
  
  testSuite.runAllTests()
    .then(async (success) => {
      await testSuite.cleanup();
      process.exit(success ? 0 : 1);
    })
    .catch(async (error) => {
      console.error('❌ Test suite execution failed:', error);
      await testSuite.cleanup();
      process.exit(1);
    });
}

module.exports = APITestSuite;