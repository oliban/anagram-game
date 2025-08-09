#!/usr/bin/env node

/**
 * Phase 4 Validation Test Suite
 * 
 * Tests core validation and security features for Phase 4.1/4.2:
 * - Socket ID type validation and input sanitization
 * - Player response format validation (lastSeen, phrasesCompleted fields)
 * - UUID format enforcement and database validation
 * - Real phrase ID usage vs fake ID rejection
 * - HTTP status code compliance (201 vs 200)
 * - App version compatibility and clean architecture
 */

const axios = require('axios');

class Phase4ValidationTests {
  constructor() {
    this.baseURL = 'http://localhost:3000';
    this.results = {
      passed: 0,
      failed: 0,
      skipped: 0
    };
    this.testPlayers = [];
    this.testPhrases = [];
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = level === 'error' ? '❌' : level === 'success' ? '✅' : level === 'warn' ? '⚠️' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
  }

  logResult(testName, passed, details = '', category = '') {
    const status = passed ? '✅ PASS' : '❌ FAIL';
    const categoryPrefix = category ? `[${category}] ` : '';
    console.log(`${status} ${categoryPrefix}${testName}${details ? ` - ${details}` : ''}`);
    
    if (passed) {
      this.results.passed++;
    } else {
      this.results.failed++;
    }
  }

  async makeRequest(method, endpoint, data = null, expectedStatus = 200, headers = {}) {
    try {
      const config = {
        method,
        url: `${this.baseURL}${endpoint}`,
        timeout: 10000,
        headers: {
          'Content-Type': 'application/json',
          ...headers
        }
      };

      if (data) {
        config.data = data;
      }

      const response = await axios(config);
      
      // Handle array of expected status codes
      const expectedStatuses = Array.isArray(expectedStatus) ? expectedStatus : [expectedStatus];
      const statusMatch = expectedStatuses.includes(response.status);
      
      return {
        success: statusMatch,
        status: response.status,
        data: response.data,
        error: statusMatch ? null : `Expected status ${expectedStatus}, got ${response.status}`
      };
    } catch (error) {
      const status = error.response?.status || 0;
      const expectedStatuses = Array.isArray(expectedStatus) ? expectedStatus : [expectedStatus];
      const statusMatch = expectedStatuses.includes(status);
      
      return {
        success: statusMatch,
        status,
        data: error.response?.data || null,
        error: statusMatch ? null : (error.response?.data?.error || error.message)
      };
    }
  }

  async createTestPlayer(name, socketId = null) {
    const uniqueName = `${name}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const result = await this.makeRequest('POST', '/api/players/register', {
      name: uniqueName,
      socketId: socketId || `test-socket-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
    }, 201);

    if (result.success && result.data.player) {
      this.testPlayers.push(result.data.player);
      return result.data.player;
    }
    
    throw new Error(`Failed to create test player: ${result.error}`);
  }

  // 1. Socket ID Type Validation Tests
  async testSocketIdTypeValidation() {
    this.log('Testing Socket ID type validation...');
    let allPassed = true;

    const invalidTests = [
      { socketId: 123, name: "ValidName1", description: "number socketId" },
      { socketId: true, name: "ValidName2", description: "boolean socketId" },
      { socketId: {}, name: "ValidName3", description: "object socketId" },
      { socketId: [], name: "ValidName4", description: "array socketId" }
    ];
    
    for (const test of invalidTests) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name: `${test.name}_${Date.now()}`,
        socketId: test.socketId
      }, 400);
      
      const passed = result.success && result.data?.error?.includes('Socket ID must be a string or null');
      this.logResult(`Socket ID validation - ${test.description}`, passed, 
        passed ? 'Correctly rejected' : `Got: ${result.status} ${result.error}`, 'SocketID');
      allPassed = allPassed && passed;
    }

    return allPassed;
  }

  async testValidSocketIdTypes() {
    this.log('Testing valid Socket ID types...');
    let allPassed = true;

    const validTests = [
      { socketId: "valid-string-id", name: "ValidSocketString" },
      { socketId: null, name: "ValidSocketNull" },
      { socketId: undefined, name: "ValidSocketUndefined" }
    ];
    
    for (const test of validTests) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name: `${test.name}_${Date.now()}`,
        socketId: test.socketId
      }, 201);
      
      const passed = result.success;
      this.logResult(`Valid socket ID - ${test.socketId === null ? 'null' : test.socketId === undefined ? 'undefined' : 'string'}`, 
        passed, passed ? 'Accepted correctly' : `Error: ${result.error}`, 'SocketID');
      allPassed = allPassed && passed;
      
      if (passed && result.data.player) {
        this.testPlayers.push(result.data.player);
      }
    }

    return allPassed;
  }

  // 2. Player Model Response Format Tests
  async testPlayerResponseFormat() {
    this.log('Testing Player response format...');
    
    const result = await this.makeRequest('POST', '/api/players/register', {
      name: `FormatTestPlayer_${Date.now()}`,
      socketId: "format-test-socket"
    }, 201);
    
    if (!result.success) {
      this.logResult('Player response format test', false, `Registration failed: ${result.error}`, 'ResponseFormat');
      return false;
    }
    
    const player = result.data.player;
    let allPassed = true;
    
    // Test required fields
    const requiredFields = [
      { field: 'id', type: 'string' },
      { field: 'name', type: 'string' },
      { field: 'lastSeen', type: 'string' }, // ISO date string
      { field: 'isActive', type: 'boolean' },
      { field: 'phrasesCompleted', type: 'number' }
    ];
    
    for (const { field, type } of requiredFields) {
      const hasField = player.hasOwnProperty(field);
      const correctType = hasField && typeof player[field] === type;
      const passed = hasField && correctType;
      
      this.logResult(`Player has ${field} field (${type})`, passed, 
        passed ? `✓ ${player[field]}` : `Missing or wrong type`, 'ResponseFormat');
      allPassed = allPassed && passed;
    }
    
    // Test deprecated fields are NOT present
    const deprecatedFields = ['connectedAt'];
    for (const field of deprecatedFields) {
      const absent = !player.hasOwnProperty(field);
      this.logResult(`Player does NOT have deprecated ${field} field`, absent, 
        absent ? 'Correctly absent' : `Should not be present: ${player[field]}`, 'ResponseFormat');
      allPassed = allPassed && absent;
    }
    
    if (result.data.player) {
      this.testPlayers.push(result.data.player);
    }
    
    return allPassed;
  }

  async testOnlinePlayersResponseFormat() {
    this.log('Testing online players response format...');
    
    const result = await this.makeRequest('GET', '/api/players/online', null, 200);
    
    if (!result.success) {
      this.logResult('Online players response format test', false, `Request failed: ${result.error}`, 'ResponseFormat');
      return false;
    }
    
    if (!result.data.players || result.data.players.length === 0) {
      this.logResult('Online players response format test', false, 'No players found to test format', 'ResponseFormat');
      return false;
    }
    
    const player = result.data.players[0];
    let allPassed = true;
    
    // Same validation as registration response
    const hasLastSeen = player.hasOwnProperty('lastSeen');
    const hasPhrasesCompleted = player.hasOwnProperty('phrasesCompleted') && typeof player.phrasesCompleted === 'number';
    const noConnectedAt = !player.hasOwnProperty('connectedAt');
    
    this.logResult('Online player has lastSeen field', hasLastSeen, 
      hasLastSeen ? '✓' : 'Missing lastSeen', 'ResponseFormat');
    this.logResult('Online player has phrasesCompleted field', hasPhrasesCompleted, 
      hasPhrasesCompleted ? `✓ ${player.phrasesCompleted}` : 'Missing or wrong type', 'ResponseFormat');
    this.logResult('Online player does NOT have connectedAt', noConnectedAt, 
      noConnectedAt ? '✓' : 'Should not have connectedAt', 'ResponseFormat');
    
    allPassed = hasLastSeen && hasPhrasesCompleted && noConnectedAt;
    return allPassed;
  }

  // 3. Real Phrase ID Tests
  async testRealPhraseIdUsage() {
    this.log('Testing real phrase ID usage...');
    
    if (this.testPlayers.length < 2) {
      await this.createTestPlayer("PhraseTestPlayer1");
      await this.createTestPlayer("PhraseTestPlayer2");
    }
    
    const player1 = this.testPlayers[0];
    const player2 = this.testPlayers[1];
    
    // Create a real phrase
    const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: "test phrase for skip validation",
      senderId: player1.id,
      targetId: player2.id
    }, 201);
    
    if (!phraseResult.success) {
      this.logResult('Real phrase ID test setup', false, `Failed to create phrase: ${phraseResult.error}`, 'RealPhraseID');
      return false;
    }
    
    const realPhraseId = phraseResult.data.phrase.id;
    this.testPhrases.push(phraseResult.data.phrase);
    
    // Test skip with real phrase ID
    const skipResult = await this.makeRequest('POST', `/api/phrases/${realPhraseId}/skip`, {
      playerId: player2.id
    }, 200);
    
    const skipPassed = skipResult.success;
    this.logResult('Skip with real phrase ID', skipPassed, 
      skipPassed ? `Phrase ${realPhraseId} skipped` : `Error: ${skipResult.error}`, 'RealPhraseID');
    
    // Create another phrase for consume test
    const phraseResult2 = await this.makeRequest('POST', '/api/phrases/create', {
      content: "test phrase for consume validation",
      senderId: player1.id,
      targetId: player2.id
    }, 201);
    
    if (phraseResult2.success) {
      const consumeResult = await this.makeRequest('POST', `/api/phrases/${phraseResult2.data.phrase.id}/consume`, {}, 200);
      const consumePassed = consumeResult.success;
      this.logResult('Consume with real phrase ID', consumePassed, 
        consumePassed ? `Phrase ${phraseResult2.data.phrase.id} consumed` : `Error: ${consumeResult.error}`, 'RealPhraseID');
      
      return skipPassed && consumePassed;
    }
    
    return skipPassed;
  }

  async testFakePhraseIdRejection() {
    this.log('Testing fake phrase ID rejection...');
    
    if (this.testPlayers.length === 0) {
      await this.createTestPlayer("FakeIdTestPlayer");
    }
    
    const fakeIds = [
      "fake-phrase-id",
      "test-phrase-id", 
      "not-a-real-uuid",
      "12345"
    ];
    
    let allPassed = true;
    
    for (const fakeId of fakeIds) {
      const skipResult = await this.makeRequest('POST', `/api/phrases/${fakeId}/skip`, {
        playerId: this.testPlayers[0].id
      }, 404);
      
      const passed = skipResult.status === 404;
      this.logResult(`Fake phrase ID rejection - ${fakeId}`, passed, 
        passed ? 'Correctly rejected with 404' : `Got: ${skipResult.status}`, 'FakePhraseID');
      allPassed = allPassed && passed;
    }
    
    return allPassed;
  }

  // 4. HTTP Status Code Tests
  async testCorrectStatusCodes() {
    this.log('Testing correct HTTP status codes...');
    let allPassed = true;

    // Player registration should return 201
    const regResult = await this.makeRequest('POST', '/api/players/register', {
      name: `StatusTestPlayer_${Date.now()}`,
      socketId: "status-test"
    }, 201);
    
    const regPassed = regResult.status === 201;
    this.logResult('Player registration returns 201', regPassed, 
      regPassed ? 'Correct status code' : `Got: ${regResult.status}`, 'StatusCodes');
    allPassed = allPassed && regPassed;
    
    if (regResult.data?.player) {
      this.testPlayers.push(regResult.data.player);
    }
    
    // Phrase creation should return 201
    if (this.testPlayers.length >= 2) {
      const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
        content: "status test phrase",
        senderId: this.testPlayers[0].id,
        targetId: this.testPlayers[1].id
      }, 201);
      
      const phrasePassed = phraseResult.status === 201;
      this.logResult('Phrase creation returns 201', phrasePassed, 
        phrasePassed ? 'Correct status code' : `Got: ${phraseResult.status}`, 'StatusCodes');
      allPassed = allPassed && phrasePassed;
    }
    
    // GET requests should return 200
    const playersResult = await this.makeRequest('GET', '/api/players/online', null, 200);
    const playersPassed = playersResult.status === 200;
    this.logResult('GET players/online returns 200', playersPassed, 
      playersPassed ? 'Correct status code' : `Got: ${playersResult.status}`, 'StatusCodes');
    
    const statusResult = await this.makeRequest('GET', '/api/status', null, 200);
    const statusPassed = statusResult.status === 200;
    this.logResult('GET status returns 200', statusPassed, 
      statusPassed ? 'Correct status code' : `Got: ${statusResult.status}`, 'StatusCodes');
    
    allPassed = allPassed && playersPassed && statusPassed;
    return allPassed;
  }

  // 5. UUID Format Enforcement Tests
  async testUUIDFormatEnforcement() {
    this.log('Testing UUID format enforcement...');
    
    const oldFormatIds = [
      "player_1751880982707_8bdfn6lb7",  // From server logs
      "player_1751882240322_tznkz8ai6",  // From server logs
      "user_123456789",
      "player-simple-id"
    ];
    
    let allPassed = true;
    
    for (const oldId of oldFormatIds) {
      const result = await this.makeRequest('GET', `/api/phrases/for/${oldId}`, null, 404);
      
      // Should fail with 404 (Player not found) - old format IDs are rejected by database layer
      const passed = result.status === 404;
      const playerNotFoundError = result.error && result.error.includes('Player not found');
      
      this.logResult(`UUID format enforcement - ${oldId}`, passed, 
        passed ? `Correctly rejected (404 - Player not found)` : `Got status ${result.status}: ${result.error}`, 'UUIDFormat');
      allPassed = allPassed && passed;
    }
    
    return allPassed;
  }

  async testValidUUIDAcceptance() {
    this.log('Testing valid UUID acceptance...');
    
    // Use UUIDs from test players we created
    const validUUIDs = this.testPlayers.slice(0, 2).map(p => p.id);
    
    if (validUUIDs.length === 0) {
      this.logResult('Valid UUID acceptance test', false, 'No valid UUIDs to test', 'UUIDFormat');
      return false;
    }
    
    let allPassed = true;
    
    for (const uuid of validUUIDs) {
      const result = await this.makeRequest('GET', `/api/phrases/for/${uuid}`, null, [200, 404]);
      
      // Should not fail with UUID format errors (200 or 404 are both OK)
      const passed = result.status === 200 || result.status === 404;
      const noUuidError = !result.error || !result.error.toLowerCase().includes('uuid');
      
      this.logResult(`Valid UUID acceptance - ${uuid}`, passed && noUuidError, 
        passed ? `Accepted (${result.status})` : `UUID format error: ${result.error}`, 'UUIDFormat');
      allPassed = allPassed && passed && noUuidError;
    }
    
    return allPassed;
  }

  // 6. App Version Compatibility Tests
  async testAppVersionCompatibility() {
    this.log('Testing app version compatibility...');
    
    // Test with version 1.7 headers
    const modernResult = await this.makeRequest('POST', '/api/players/register', {
      name: `ModernAppUser_${Date.now()}`,
      socketId: "modern-socket"
    }, 201, {
      'User-Agent': 'AnagramGame/1.7',
      'App-Version': '1.7'
    });
    
    const modernPassed = modernResult.success;
    this.logResult('App version 1.7 compatibility', modernPassed, 
      modernPassed ? 'Registration successful' : `Error: ${modernResult.error}`, 'AppVersion');
    
    if (modernResult.data?.player) {
      const playerId = modernResult.data.player.id;
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
      const validUuid = uuidRegex.test(playerId);
      
      this.logResult('Generated player ID is valid UUID', validUuid, 
        validUuid ? `✓ ${playerId}` : `Invalid format: ${playerId}`, 'AppVersion');
      
      return modernPassed && validUuid;
    }
    
    return modernPassed;
  }

  async cleanup() {
    this.log('Cleaning up test data...');
    // Test players and phrases will be cleaned up by existing test infrastructure
  }

  async runAllTests() {
    this.log('\n🧪 Starting Phase 4 Validation Tests...');
    this.log('===============================================');

    try {
      let overallSuccess = true;

      // Run all test categories
      overallSuccess = await this.testSocketIdTypeValidation() && overallSuccess;
      overallSuccess = await this.testValidSocketIdTypes() && overallSuccess;
      overallSuccess = await this.testPlayerResponseFormat() && overallSuccess;
      overallSuccess = await this.testOnlinePlayersResponseFormat() && overallSuccess;
      overallSuccess = await this.testRealPhraseIdUsage() && overallSuccess;
      overallSuccess = await this.testFakePhraseIdRejection() && overallSuccess;
      overallSuccess = await this.testCorrectStatusCodes() && overallSuccess;
      overallSuccess = await this.testUUIDFormatEnforcement() && overallSuccess;
      overallSuccess = await this.testValidUUIDAcceptance() && overallSuccess;
      overallSuccess = await this.testAppVersionCompatibility() && overallSuccess;

      // Generate summary
      this.log('\n📊 PHASE 4 VALIDATION TEST RESULTS');
      this.log('=====================================');
      this.log(`✅ Passed: ${this.results.passed}`);
      this.log(`❌ Failed: ${this.results.failed}`);
      this.log(`⏭️ Skipped: ${this.results.skipped}`);
      
      const total = this.results.passed + this.results.failed + this.results.skipped;
      const successRate = total > 0 ? Math.round((this.results.passed / total) * 100) : 0;
      this.log(`🎯 Total: ${total}`);
      this.log(`📈 Success Rate: ${successRate}%`);
      
      if (overallSuccess) {
        this.log('🚀 ALL PHASE 4 VALIDATION FEATURES WORKING CORRECTLY!', 'success');
      } else {
        this.log('⚠️ Some Phase 4 validation features need attention', 'warn');
      }

      return overallSuccess;

    } catch (error) {
      this.log(`❌ Test suite failed: ${error.message}`, 'error');
      return false;
    }
  }
}

// Run if executed directly
if (require.main === module) {
  const suite = new Phase4ValidationTests();
  suite.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('❌ Test runner failed:', error);
    process.exit(1);
  });
}

module.exports = Phase4ValidationTests;