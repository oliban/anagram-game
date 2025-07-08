#!/usr/bin/env node

/**
 * Phase 4.2 Global Phrase Bank Tests
 * 
 * Tests the new GET /api/phrases/global endpoint with comprehensive options:
 * - Pagination support (limit, offset)
 * - Difficulty filtering (1-5)
 * - Approval status filtering
 * - Response format validation
 * - Error handling
 * 
 * Usage: node test_phase4_global_phrases.js
 */

const axios = require('axios');

const SERVER_URL = 'http://localhost:3000';

class Phase4GlobalPhrasesTests {
  constructor() {
    this.results = {
      passed: 0,
      failed: 0,
      skipped: 0,
      details: []
    };
    this.testPlayers = [];
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = level === 'error' ? '❌' : level === 'success' ? '✅' : level === 'warn' ? '⚠️' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
  }

  logResult(testName, passed, details = '') {
    const status = passed ? '✅ PASS' : '❌ FAIL';
    console.log(`${status} [Phase4.2] ${testName}`);
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

  // Test basic global phrases retrieval
  async testBasicGlobalPhrases() {
    this.log('Testing basic global phrases retrieval...');
    
    const result = await this.makeRequest('GET', '/api/phrases/global');

    const passed = result.success && 
      result.data.success &&
      Array.isArray(result.data.phrases) &&
      result.data.pagination &&
      typeof result.data.pagination.total === 'number' &&
      typeof result.data.pagination.count === 'number' &&
      result.data.filters &&
      result.data.timestamp;

    this.logResult('Basic global phrases retrieval',
      passed,
      passed ? `Retrieved ${result.data.phrases.length} phrases` : `Error: ${result.error || result.data?.error}`);

    return passed;
  }

  // Test pagination functionality
  async testPagination() {
    this.log('Testing pagination functionality...');
    
    // Test with small limit
    const result1 = await this.makeRequest('GET', '/api/phrases/global?limit=2');
    const test1Passed = result1.success && 
      result1.data.phrases.length <= 2 &&
      result1.data.pagination.limit === 2;

    // Test with offset
    const result2 = await this.makeRequest('GET', '/api/phrases/global?limit=2&offset=1');
    const test2Passed = result2.success && 
      result2.data.pagination.offset === 1;

    // Test pagination metadata
    const result3 = await this.makeRequest('GET', '/api/phrases/global?limit=5');
    const test3Passed = result3.success && 
      typeof result3.data.pagination.hasMore === 'boolean' &&
      result3.data.pagination.count === result3.data.phrases.length;

    const allPassed = test1Passed && test2Passed && test3Passed;

    this.logResult('Pagination - limit parameter',
      test1Passed,
      test1Passed ? 'Limit parameter working correctly' : 'Limit parameter failed');

    this.logResult('Pagination - offset parameter',
      test2Passed,
      test2Passed ? 'Offset parameter working correctly' : 'Offset parameter failed');

    this.logResult('Pagination - metadata validation',
      test3Passed,
      test3Passed ? 'Pagination metadata correct' : 'Pagination metadata incorrect');

    return allPassed;
  }

  // Test difficulty filtering
  async testDifficultyFiltering() {
    this.log('Testing difficulty filtering...');
    
    // Test filtering by difficulty level 1
    const result1 = await this.makeRequest('GET', '/api/phrases/global?difficulty=1');
    const test1Passed = result1.success && 
      result1.data.phrases.every(p => p.difficultyLevel === 1) &&
      result1.data.filters.difficulty === 1;

    // Test filtering by difficulty level 2
    const result2 = await this.makeRequest('GET', '/api/phrases/global?difficulty=2');
    const test2Passed = result2.success && 
      result2.data.phrases.every(p => p.difficultyLevel === 2) &&
      result2.data.filters.difficulty === 2;

    // Test filtering by difficulty level 3
    const result3 = await this.makeRequest('GET', '/api/phrases/global?difficulty=3');
    const test3Passed = result3.success && 
      result3.data.phrases.every(p => p.difficultyLevel === 3) &&
      result3.data.filters.difficulty === 3;

    // Test invalid difficulty (should ignore filter)
    const result4 = await this.makeRequest('GET', '/api/phrases/global?difficulty=10');
    const test4Passed = result4.success && 
      result4.data.filters.difficulty === 'all';

    this.logResult('Difficulty filtering - level 1',
      test1Passed,
      test1Passed ? `Found ${result1.data.phrases.length} level 1 phrases` : 'Level 1 filtering failed');

    this.logResult('Difficulty filtering - level 2',
      test2Passed,
      test2Passed ? `Found ${result2.data.phrases.length} level 2 phrases` : 'Level 2 filtering failed');

    this.logResult('Difficulty filtering - level 3',
      test3Passed,
      test3Passed ? `Found ${result3.data.phrases.length} level 3 phrases` : 'Level 3 filtering failed');

    this.logResult('Difficulty filtering - invalid value',
      test4Passed,
      test4Passed ? 'Invalid difficulty ignored correctly' : 'Invalid difficulty not handled');

    return test1Passed && test2Passed && test3Passed && test4Passed;
  }

  // Test approval status filtering
  async testApprovalFiltering() {
    this.log('Testing approval status filtering...');
    
    // Test approved only (default)
    const result1 = await this.makeRequest('GET', '/api/phrases/global');
    const test1Passed = result1.success && 
      result1.data.phrases.every(p => p.isApproved === true) &&
      result1.data.filters.approved === true;

    // Test including unapproved
    const result2 = await this.makeRequest('GET', '/api/phrases/global?approved=false');
    const test2Passed = result2.success && 
      result2.data.filters.approved === false;

    this.logResult('Approval filtering - approved only',
      test1Passed,
      test1Passed ? 'Only approved phrases returned by default' : 'Approval filtering failed');

    this.logResult('Approval filtering - include unapproved',
      test2Passed,
      test2Passed ? 'Unapproved filter working' : 'Unapproved filtering failed');

    return test1Passed && test2Passed;
  }

  // Test response format validation
  async testResponseFormat() {
    this.log('Testing response format validation...');
    
    const result = await this.makeRequest('GET', '/api/phrases/global?limit=1');

    const hasRequiredFields = result.success &&
      result.data.success &&
      Array.isArray(result.data.phrases) &&
      result.data.pagination &&
      result.data.filters &&
      result.data.timestamp;

    let phraseFormatValid = true;
    if (result.data.phrases.length > 0) {
      const phrase = result.data.phrases[0];
      phraseFormatValid = phrase.id &&
        phrase.content &&
        phrase.hint &&
        typeof phrase.difficultyLevel === 'number' &&
        phrase.phraseType &&
        phrase.language &&
        typeof phrase.usageCount === 'number' &&
        typeof phrase.isApproved === 'boolean' &&
        phrase.createdAt &&
        phrase.createdByName;
    }

    const paginationValid = result.data.pagination.limit !== undefined &&
      result.data.pagination.offset !== undefined &&
      result.data.pagination.total !== undefined &&
      result.data.pagination.count !== undefined &&
      result.data.pagination.hasMore !== undefined;

    const filtersValid = result.data.filters.difficulty !== undefined &&
      result.data.filters.approved !== undefined;

    this.logResult('Response format - top level fields',
      hasRequiredFields,
      hasRequiredFields ? 'All required top-level fields present' : 'Missing top-level fields');

    this.logResult('Response format - phrase objects',
      phraseFormatValid,
      phraseFormatValid ? 'Phrase objects have correct format' : 'Phrase objects missing fields');

    this.logResult('Response format - pagination object',
      paginationValid,
      paginationValid ? 'Pagination object correct' : 'Pagination object incomplete');

    this.logResult('Response format - filters object',
      filtersValid,
      filtersValid ? 'Filters object correct' : 'Filters object incomplete');

    return hasRequiredFields && phraseFormatValid && paginationValid && filtersValid;
  }

  // Test limit boundaries
  async testLimitBoundaries() {
    this.log('Testing limit boundaries...');
    
    // Test maximum limit (should be capped at 100)
    const result1 = await this.makeRequest('GET', '/api/phrases/global?limit=500');
    const test1Passed = result1.success && 
      result1.data.pagination.limit <= 100;

    // Test zero limit (should default to 50)
    const result2 = await this.makeRequest('GET', '/api/phrases/global?limit=0');
    const test2Passed = result2.success && 
      result2.data.pagination.limit > 0;

    // Test negative limit (should default to 50)
    const result3 = await this.makeRequest('GET', '/api/phrases/global?limit=-10');
    const test3Passed = result3.success && 
      result3.data.pagination.limit > 0;

    this.logResult('Limit boundaries - maximum cap',
      test1Passed,
      test1Passed ? `Limit capped at ${result1.data.pagination.limit}` : 'Maximum limit not enforced');

    this.logResult('Limit boundaries - zero limit',
      test2Passed,
      test2Passed ? `Zero limit handled, defaulted to ${result2.data.pagination.limit}` : 'Zero limit not handled');

    this.logResult('Limit boundaries - negative limit',
      test3Passed,
      test3Passed ? `Negative limit handled, defaulted to ${result3.data.pagination.limit}` : 'Negative limit not handled');

    return test1Passed && test2Passed && test3Passed;
  }

  // Test error handling
  async testErrorHandling() {
    this.log('Testing error handling...');
    
    // All error scenarios should be handled gracefully and return valid responses
    // since the database is available and the endpoint should be robust

    // Test with invalid query parameters (should not break)
    const result1 = await this.makeRequest('GET', '/api/phrases/global?invalid=true&difficulty=abc');
    const test1Passed = result1.success && result1.data.success;

    this.logResult('Error handling - invalid parameters',
      test1Passed,
      test1Passed ? 'Invalid parameters handled gracefully' : 'Invalid parameters caused errors');

    return test1Passed;
  }

  // Test combined filters
  async testCombinedFilters() {
    this.log('Testing combined filters...');
    
    // Test difficulty + limit + offset
    const result1 = await this.makeRequest('GET', '/api/phrases/global?difficulty=2&limit=3&offset=0');
    const test1Passed = result1.success && 
      result1.data.phrases.every(p => p.difficultyLevel === 2) &&
      result1.data.pagination.limit === 3 &&
      result1.data.filters.difficulty === 2;

    // Test difficulty + approval status
    const result2 = await this.makeRequest('GET', '/api/phrases/global?difficulty=1&approved=true');
    const test2Passed = result2.success && 
      result2.data.phrases.every(p => p.difficultyLevel === 1 && p.isApproved === true) &&
      result2.data.filters.difficulty === 1 &&
      result2.data.filters.approved === true;

    this.logResult('Combined filters - difficulty + pagination',
      test1Passed,
      test1Passed ? 'Difficulty and pagination filters work together' : 'Combined filtering failed');

    this.logResult('Combined filters - difficulty + approval',
      test2Passed,
      test2Passed ? 'Difficulty and approval filters work together' : 'Combined filtering failed');

    return test1Passed && test2Passed;
  }

  // Run all Phase 4.2 tests
  async runAllTests() {
    this.log('🧪 Starting Phase 4.2 Global Phrase Bank Tests...\n');
    
    const testSuites = [
      { name: 'Basic Global Phrases Retrieval', test: () => this.testBasicGlobalPhrases() },
      { name: 'Pagination Functionality', test: () => this.testPagination() },
      { name: 'Difficulty Filtering', test: () => this.testDifficultyFiltering() },
      { name: 'Approval Status Filtering', test: () => this.testApprovalFiltering() },
      { name: 'Response Format Validation', test: () => this.testResponseFormat() },
      { name: 'Limit Boundaries', test: () => this.testLimitBoundaries() },
      { name: 'Error Handling', test: () => this.testErrorHandling() },
      { name: 'Combined Filters', test: () => this.testCombinedFilters() }
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
    this.log('\n📊 Phase 4.2 Global Phrase Bank Test Summary:');
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
    this.log(`\n🎉 Phase 4.2 Global Phrase Bank Tests: ${overallPassed ? 'ALL PASSED' : 'SOME FAILED'}`);
    
    return overallPassed;
  }

  // Cleanup
  async cleanup() {
    this.log('🧹 Phase 4.2 test cleanup completed');
  }
}

// Run tests if script is executed directly
if (require.main === module) {
  const testSuite = new Phase4GlobalPhrasesTests();
  
  testSuite.runAllTests()
    .then(async (success) => {
      await testSuite.cleanup();
      process.exit(success ? 0 : 1);
    })
    .catch(async (error) => {
      console.error('❌ Phase 4.2 global phrase bank tests execution failed:', error);
      await testSuite.cleanup();
      process.exit(1);
    });
}

module.exports = Phase4GlobalPhrasesTests;