/**
 * Test Suite for Difficulty Range Filtering (Phase 4.7.3)
 * Tests the new minDifficulty and maxDifficulty parameters in /api/phrases/global
 */

const http = require('http');
const querystring = require('querystring');

class DifficultyFilteringTests {
  constructor() {
    this.baseUrl = 'http://localhost:3000';
    this.testResults = [];
    this.totalTests = 0;
    this.passedTests = 0;
  }

  async makeRequest(method, path, data = null, expectedStatus = 200) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const options = {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method: method,
        headers: {
          'Content-Type': 'application/json',
        }
      };

      const req = http.request(options, (res) => {
        let responseBody = '';
        res.on('data', (chunk) => {
          responseBody += chunk;
        });
        
        res.on('end', () => {
          try {
            const jsonResponse = JSON.parse(responseBody);
            resolve({
              status: res.statusCode,
              data: jsonResponse,
              rawBody: responseBody
            });
          } catch (e) {
            resolve({
              status: res.statusCode,
              data: null,
              rawBody: responseBody,
              parseError: e.message
            });
          }
        });
      });

      req.on('error', (err) => {
        reject(err);
      });

      if (data) {
        req.write(JSON.stringify(data));
      }
      
      req.end();
    });
  }

  logTest(name, passed, details = '') {
    this.totalTests++;
    if (passed) {
      this.passedTests++;
      console.log(`    ✅ ${name}`);
    } else {
      console.log(`    ❌ ${name}`);
      if (details) console.log(`       ${details}`);
    }
    this.testResults.push({ name, passed, details });
  }

  async testBasicDifficultyFiltering() {
    console.log('📝 Testing Basic Difficulty Range Filtering:');

    // Test 1: Easy phrases (1-30)
    const easyResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=1&maxDifficulty=30&limit=5');
    const easyPassed = easyResult.status === 200 && 
                       easyResult.data.success === true &&
                       easyResult.data.phrases.every(p => p.difficultyLevel >= 1 && p.difficultyLevel <= 30);
    this.logTest('Easy phrases (1-30)', easyPassed, 
      easyPassed ? `Found ${easyResult.data.phrases.length} phrases` : 
      `Expected difficulty 1-30, got: ${easyResult.data.phrases.map(p => p.difficultyLevel).join(', ')}`);

    // Test 2: Hard phrases (70-100)
    const hardResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=70&maxDifficulty=100&limit=5');
    const hardPassed = hardResult.status === 200 && 
                       hardResult.data.success === true &&
                       hardResult.data.phrases.every(p => p.difficultyLevel >= 70 && p.difficultyLevel <= 100);
    this.logTest('Hard phrases (70-100)', hardPassed,
      hardPassed ? `Found ${hardResult.data.phrases.length} phrases` :
      `Expected difficulty 70-100, got: ${hardResult.data.phrases.map(p => p.difficultyLevel).join(', ')}`);

    // Test 3: Medium phrases (40-60)
    const mediumResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=40&maxDifficulty=60&limit=5');
    const mediumPassed = mediumResult.status === 200 && 
                         mediumResult.data.success === true &&
                         mediumResult.data.phrases.every(p => p.difficultyLevel >= 40 && p.difficultyLevel <= 60);
    this.logTest('Medium phrases (40-60)', mediumPassed,
      mediumPassed ? `Found ${mediumResult.data.phrases.length} phrases` :
      `Expected difficulty 40-60, got: ${mediumResult.data.phrases.map(p => p.difficultyLevel).join(', ')}`);
  }

  async testEdgeCases() {
    console.log('🧪 Testing Edge Cases:');

    // Test 1: Only minDifficulty
    const minOnlyResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=50&limit=3');
    const minOnlyPassed = minOnlyResult.status === 200 && 
                          minOnlyResult.data.phrases.every(p => p.difficultyLevel >= 50);
    this.logTest('Only minDifficulty (≥50)', minOnlyPassed,
      minOnlyPassed ? `All phrases ≥50 difficulty` :
      `Expected ≥50, got: ${minOnlyResult.data.phrases.map(p => p.difficultyLevel).join(', ')}`);

    // Test 2: Only maxDifficulty  
    const maxOnlyResult = await this.makeRequest('GET', '/api/phrases/global?maxDifficulty=30&limit=3');
    const maxOnlyPassed = maxOnlyResult.status === 200 && 
                          maxOnlyResult.data.phrases.every(p => p.difficultyLevel <= 30);
    this.logTest('Only maxDifficulty (≤30)', maxOnlyPassed,
      maxOnlyPassed ? `All phrases ≤30 difficulty` :
      `Expected ≤30, got: ${maxOnlyResult.data.phrases.map(p => p.difficultyLevel).join(', ')}`);

    // Test 3: Invalid range (min > max)
    const invalidResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=80&maxDifficulty=20&limit=3');
    const invalidPassed = invalidResult.status === 200 && invalidResult.data.phrases.length === 0;
    this.logTest('Invalid range (min > max)', invalidPassed,
      invalidPassed ? 'Correctly returned no results' : 'Should return empty results for invalid range');

    // Test 4: Out of bounds values
    const oobResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=150&maxDifficulty=200&limit=3');
    const oobPassed = oobResult.status === 200 && oobResult.data.phrases.length === 0;
    this.logTest('Out of bounds values (150-200)', oobPassed,
      oobPassed ? 'Correctly handled out of bounds' : 'Should handle out of bounds gracefully');
  }

  async testCombinedFilters() {
    console.log('🔗 Testing Combined Filters:');

    // Test 1: Difficulty range + approved filter
    const combinedResult = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=30&maxDifficulty=70&approved=true&limit=5');
    const combinedPassed = combinedResult.status === 200 && 
                           combinedResult.data.phrases.every(p => 
                             p.difficultyLevel >= 30 && p.difficultyLevel <= 70 && p.isApproved === true);
    this.logTest('Difficulty range + approved filter', combinedPassed,
      combinedPassed ? 'Filters working together correctly' : 'Combined filters not working properly');

    // Test 2: Legacy difficulty filter compatibility
    const legacyResult = await this.makeRequest('GET', '/api/phrases/global?difficulty=1&limit=3');
    const legacyPassed = legacyResult.status === 200;
    this.logTest('Legacy difficulty filter compatibility', legacyPassed,
      legacyPassed ? 'Legacy filter still works' : 'Legacy filter broken');

    // Test 3: Pagination with difficulty filters
    const page1Result = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=1&maxDifficulty=100&limit=2&offset=0');
    const page2Result = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=1&maxDifficulty=100&limit=2&offset=2');
    const paginationPassed = page1Result.status === 200 && page2Result.status === 200 &&
                             page1Result.data.pagination.offset === 0 && page2Result.data.pagination.offset === 2;
    this.logTest('Pagination with difficulty filters', paginationPassed,
      paginationPassed ? 'Pagination working with filters' : 'Pagination broken with filters');
  }

  async testResponseFormat() {
    console.log('📋 Testing Response Format:');

    const result = await this.makeRequest('GET', '/api/phrases/global?minDifficulty=25&maxDifficulty=75&limit=2');
    
    // Test response structure
    const hasRequiredFields = result.data.success !== undefined &&
                              result.data.phrases !== undefined &&
                              result.data.pagination !== undefined &&
                              result.data.filters !== undefined &&
                              result.data.timestamp !== undefined;
    this.logTest('Response has required fields', hasRequiredFields,
      hasRequiredFields ? 'All required fields present' : 'Missing required response fields');

    // Test phrase structure
    if (result.data.phrases.length > 0) {
      const phrase = result.data.phrases[0];
      const phraseHasFields = phrase.id !== undefined &&
                              phrase.content !== undefined &&
                              phrase.difficultyLevel !== undefined &&
                              phrase.hint !== undefined;
      this.logTest('Phrase objects have required fields', phraseHasFields,
        phraseHasFields ? 'Phrase structure correct' : 'Phrase missing required fields');
    }

    // Test pagination structure
    const pagination = result.data.pagination;
    const paginationValid = pagination.limit !== undefined &&
                            pagination.offset !== undefined &&
                            pagination.total !== undefined &&
                            pagination.count !== undefined &&
                            pagination.hasMore !== undefined;
    this.logTest('Pagination structure correct', paginationValid,
      paginationValid ? 'Pagination fields present' : 'Pagination structure invalid');
  }

  async runAllTests() {
    console.log('🧪 TESTING: Difficulty Range Filtering (Phase 4.7.3)\\n');
    
    try {
      await this.testBasicDifficultyFiltering();
      console.log();
      await this.testEdgeCases();
      console.log();
      await this.testCombinedFilters();
      console.log();
      await this.testResponseFormat();
      
      console.log();
      console.log('='.repeat(60));
      console.log('📊 TEST RESULTS:');
      console.log(`   Total Tests: ${this.totalTests}`);
      console.log(`   Passed: ${this.passedTests}`);
      console.log(`   Failed: ${this.totalTests - this.passedTests}`);
      console.log(`   Success Rate: ${((this.passedTests / this.totalTests) * 100).toFixed(1)}%`);
      
      if (this.passedTests === this.totalTests) {
        console.log('   🎉 ALL TESTS PASSED!');
        return true;
      } else {
        console.log('   ⚠️ Some tests failed');
        return false;
      }
    } catch (error) {
      console.error('❌ Test suite failed:', error.message);
      return false;
    }
  }
}

// Export for use in other test files
module.exports = DifficultyFilteringTests;

// Run tests if this file is executed directly
if (require.main === module) {
  const tests = new DifficultyFilteringTests();
  tests.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  });
}