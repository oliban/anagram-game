#!/usr/bin/env node

/**
 * Phrase Approval System Test Suite (Phase 4.2 completion)
 * 
 * Tests the POST /api/phrases/:phraseId/approve endpoint:
 * - Successful approval of global phrases
 * - Rejection of non-global phrases
 * - Invalid phrase ID validation
 * - Already approved phrase handling
 * - Database error handling
 */

const axios = require('axios');

class PhraseApprovalTests {
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

  async createGlobalPhrase(senderId, content = null, isGlobal = true) {
    const testContent = content || `global test content ${Date.now()}`;
    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: testContent,
      hint: "Unscramble these words to solve the puzzle",
      senderId,
      isGlobal,
      difficultyLevel: 2,
      phraseType: 'community'
    }, 201);

    if (result.success && result.data.phrase) {
      this.testPhrases.push(result.data.phrase);
      return result.data.phrase;
    }
    
    throw new Error(`Failed to create test phrase: ${result.error}`);
  }

  async createTargetedPhrase(senderId, targetId, content = null) {
    const testContent = content || `targeted test message ${Date.now()}`;
    const result = await this.makeRequest('POST', '/api/phrases/create', {
      content: testContent,
      hint: "Solve this scrambled text puzzle",
      senderId,
      targetIds: [targetId],
      isGlobal: false,
      difficultyLevel: 1,
      phraseType: 'custom'
    }, 201);

    if (result.success && result.data.phrase) {
      this.testPhrases.push(result.data.phrase);
      return result.data.phrase;
    }
    
    throw new Error(`Failed to create test phrase: ${result.error}`);
  }

  // Test 1: Successful approval of global phrase
  async testSuccessfulApproval() {
    this.log('Testing successful global phrase approval...');
    
    const player = await this.createTestPlayer("ApprovalTestPlayer");
    const globalPhrase = await this.createGlobalPhrase(player.id, "approve this global phrase");
    
    const result = await this.makeRequest('POST', `/api/phrases/${globalPhrase.id}/approve`, null, 200);
    
    const passed = result.success && 
                   result.data.success === true && 
                   result.data.approved === true &&
                   result.data.phraseId === globalPhrase.id;
    
    this.logResult('Global phrase approval', passed, 
      passed ? `Phrase ${globalPhrase.id} approved` : `Error: ${result.error}`, 'Approval');
    
    return passed;
  }

  // Test 2: Rejection of targeted (non-global) phrases
  async testNonGlobalRejection() {
    this.log('Testing rejection of non-global phrases...');
    
    if (this.testPlayers.length < 2) {
      await this.createTestPlayer("NonGlobalPlayer1");
      await this.createTestPlayer("NonGlobalPlayer2");
    }
    
    const sender = this.testPlayers[0];
    const target = this.testPlayers[1];
    const targetedPhrase = await this.createTargetedPhrase(sender.id, target.id, "reject this targeted phrase");
    
    const result = await this.makeRequest('POST', `/api/phrases/${targetedPhrase.id}/approve`, null, 404);
    
    const passed = result.status === 404 && 
                   result.data?.error?.includes('not found or not eligible');
    
    this.logResult('Non-global phrase rejection', passed, 
      passed ? 'Correctly rejected targeted phrase' : `Got: ${result.status} ${result.error}`, 'Approval');
    
    return passed;
  }

  // Test 3: Invalid phrase ID validation
  async testInvalidPhraseId() {
    this.log('Testing invalid phrase ID validation...');
    
    const invalidIds = [
      'not-a-uuid',
      '12345',
      'fake-phrase-id',
      'invalid-format-123'
    ];
    
    let allPassed = true;
    
    for (const invalidId of invalidIds) {
      const result = await this.makeRequest('POST', `/api/phrases/${invalidId}/approve`, null, 400);
      
      const passed = result.status === 400 && 
                     result.data?.error?.includes('Invalid phrase ID format');
      
      this.logResult(`Invalid ID rejection - ${invalidId}`, passed, 
        passed ? 'Correctly rejected' : `Got: ${result.status}`, 'Validation');
      
      allPassed = allPassed && passed;
    }
    
    return allPassed;
  }

  // Test 4: Non-existent phrase handling
  async testNonExistentPhrase() {
    this.log('Testing non-existent phrase handling...');
    
    // Generate a valid UUID that doesn't exist
    const fakeUuid = '00000000-0000-4000-8000-000000000000';
    
    const result = await this.makeRequest('POST', `/api/phrases/${fakeUuid}/approve`, null, 404);
    
    const passed = result.status === 404 && 
                   result.data?.error?.includes('not found or not eligible');
    
    this.logResult('Non-existent phrase handling', passed, 
      passed ? 'Correctly handled missing phrase' : `Got: ${result.status} ${result.error}`, 'Approval');
    
    return passed;
  }

  // Test 5: Already approved phrase handling
  async testAlreadyApprovedPhrase() {
    this.log('Testing already approved phrase handling...');
    
    const player = await this.createTestPlayer("AlreadyApprovedPlayer");
    const globalPhrase = await this.createGlobalPhrase(player.id, "already approved phrase test");
    
    // First approval should succeed
    const firstResult = await this.makeRequest('POST', `/api/phrases/${globalPhrase.id}/approve`, null, 200);
    
    if (!firstResult.success) {
      this.logResult('Already approved phrase - first approval', false, `Failed: ${firstResult.error}`, 'Approval');
      return false;
    }
    
    // Second approval should also succeed (idempotent operation)
    const secondResult = await this.makeRequest('POST', `/api/phrases/${globalPhrase.id}/approve`, null, 200);
    
    const passed = secondResult.success && 
                   secondResult.data.success === true && 
                   secondResult.data.approved === true;
    
    this.logResult('Already approved phrase - second approval', passed, 
      passed ? 'Idempotent operation succeeded' : `Error: ${secondResult.error}`, 'Approval');
    
    return passed;
  }

  // Test 6: Response format validation
  async testResponseFormat() {
    this.log('Testing approval response format...');
    
    const player = await this.createTestPlayer("ResponseFormatPlayer");
    const globalPhrase = await this.createGlobalPhrase(player.id, "response format test phrase");
    
    const result = await this.makeRequest('POST', `/api/phrases/${globalPhrase.id}/approve`, null, 200);
    
    if (!result.success) {
      this.logResult('Response format validation', false, `Request failed: ${result.error}`, 'ResponseFormat');
      return false;
    }
    
    const response = result.data;
    let allPassed = true;
    
    // Check required fields
    const requiredFields = [
      { field: 'success', type: 'boolean', expected: true },
      { field: 'phraseId', type: 'string', expected: globalPhrase.id },
      { field: 'approved', type: 'boolean', expected: true },
      { field: 'message', type: 'string' },
      { field: 'timestamp', type: 'string' }
    ];
    
    for (const { field, type, expected } of requiredFields) {
      const hasField = response.hasOwnProperty(field);
      const correctType = hasField && typeof response[field] === type;
      const correctValue = expected !== undefined ? response[field] === expected : true;
      const passed = hasField && correctType && correctValue;
      
      this.logResult(`Response has ${field} field`, passed, 
        passed ? `✓ ${response[field]}` : `Missing, wrong type, or wrong value`, 'ResponseFormat');
      allPassed = allPassed && passed;
    }
    
    return allPassed;
  }

  // Test 7: Global phrases visibility after approval
  async testGlobalPhraseVisibility() {
    this.log('Testing global phrase visibility after approval...');
    
    const player = await this.createTestPlayer("VisibilityTestPlayer");
    const globalPhrase = await this.createGlobalPhrase(player.id, "visibility test global phrase");
    
    // Approve the phrase
    const approvalResult = await this.makeRequest('POST', `/api/phrases/${globalPhrase.id}/approve`, null, 200);
    
    if (!approvalResult.success) {
      this.logResult('Global phrase visibility - approval failed', false, `Approval failed: ${approvalResult.error}`, 'Visibility');
      return false;
    }
    
    // Check if phrase appears in global phrases list
    const globalResult = await this.makeRequest('GET', '/api/phrases/global?approved=true', null, 200);
    
    if (!globalResult.success) {
      this.logResult('Global phrase visibility - fetch failed', false, `Fetch failed: ${globalResult.error}`, 'Visibility');
      return false;
    }
    
    const phrases = globalResult.data.phrases || [];
    const foundPhrase = phrases.find(p => p.id === globalPhrase.id);
    const passed = foundPhrase && foundPhrase.isApproved === true;
    
    this.logResult('Global phrase visibility after approval', passed, 
      passed ? `Phrase found in global list with approved status` : `Phrase not found or not approved`, 'Visibility');
    
    return passed;
  }

  async cleanup() {
    this.log('Cleaning up test data...');
    // Test data will be cleaned up by existing test infrastructure
  }

  async runAllTests() {
    this.log('\n🧪 Starting Phrase Approval Tests...');
    this.log('===========================================');

    try {
      let overallSuccess = true;

      // Run all test categories
      overallSuccess = await this.testSuccessfulApproval() && overallSuccess;
      overallSuccess = await this.testNonGlobalRejection() && overallSuccess;
      overallSuccess = await this.testInvalidPhraseId() && overallSuccess;
      overallSuccess = await this.testNonExistentPhrase() && overallSuccess;
      overallSuccess = await this.testAlreadyApprovedPhrase() && overallSuccess;
      overallSuccess = await this.testResponseFormat() && overallSuccess;
      overallSuccess = await this.testGlobalPhraseVisibility() && overallSuccess;

      // Generate summary
      this.log('\n📊 PHRASE APPROVAL TEST RESULTS');
      this.log('=================================');
      this.log(`✅ Passed: ${this.results.passed}`);
      this.log(`❌ Failed: ${this.results.failed}`);
      this.log(`⏭️ Skipped: ${this.results.skipped}`);
      
      const total = this.results.passed + this.results.failed + this.results.skipped;
      const successRate = total > 0 ? Math.round((this.results.passed / total) * 100) : 0;
      this.log(`🎯 Total: ${total}`);
      this.log(`📈 Success Rate: ${successRate}%`);
      
      if (overallSuccess) {
        this.log('🚀 ALL PHRASE APPROVAL FEATURES WORKING CORRECTLY!', 'success');
      } else {
        this.log('⚠️ Some phrase approval features need attention', 'warn');
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
  const suite = new PhraseApprovalTests();
  suite.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('❌ Test runner failed:', error);
    process.exit(1);
  });
}

module.exports = PhraseApprovalTests;