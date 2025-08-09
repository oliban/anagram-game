#!/usr/bin/env node

/**
 * Additional API Endpoints Test
 * Tests the endpoints we haven't covered yet - focused and robust
 */

const http = require('http');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🧪 Testing Additional Endpoints: ${API_URL}`);

class AdditionalEndpointsTest {
  constructor() {
    this.passed = 0;
    this.failed = 0;
  }

  log(status, message, details = '') {
    const emoji = status ? '✅' : '❌';
    console.log(`${emoji} ${message} ${details}`);
    if (status) this.passed++; else this.failed++;
  }

  async makeRequest(method, path, data = null) {
    return new Promise((resolve) => {
      const options = {
        hostname: HOST,
        port: PORT || 80,
        path: path,
        method: method,
        headers: { 'Content-Type': 'application/json' },
        timeout: 10000
      };

      const req = http.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            const parsed = body ? JSON.parse(body) : {};
            resolve({
              status: res.statusCode,
              headers: res.headers,
              data: parsed,
              success: res.statusCode >= 200 && res.statusCode < 300
            });
          } catch (e) {
            resolve({
              status: res.statusCode,
              data: body,
              success: false,
              error: 'Invalid JSON'
            });
          }
        });
      });

      req.on('error', err => resolve({ success: false, error: err.message }));
      req.on('timeout', () => resolve({ success: false, error: 'Timeout' }));

      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async testLegendPlayersEndpoint() {
    console.log('\n🏆 Testing Legends Endpoint');
    
    const result = await this.makeRequest('GET', '/api/players/legends');
    
    if (result.success && result.data.success && Array.isArray(result.data.players)) {
      const count = result.data.players.length;
      this.log(true, 'GET /api/players/legends - Structure valid', `Found ${count} legends`);
      
      // Test data structure
      if (count > 0) {
        const legend = result.data.players[0];
        if (legend.name && legend.totalScore && Array.isArray(legend.rarestEmojis)) {
          this.log(true, 'Legend data structure valid', `${legend.name}: ${legend.totalScore} points, ${legend.rarestEmojis.length} emojis`);
          
          // Test emoji collection system
          if (legend.rarestEmojis.length <= 16) {
            this.log(true, 'Emoji collection limit enforced', `${legend.rarestEmojis.length}/16 emojis`);
          } else {
            this.log(false, 'Emoji collection limit issue', `Found ${legend.rarestEmojis.length} emojis (should be ≤16)`);
          }
        } else {
          this.log(false, 'Legend data structure invalid', 'Missing required fields');
        }
      }
    } else {
      this.log(false, 'GET /api/players/legends - Failed', `Status: ${result.status}, Error: ${result.data?.error || 'Unknown'}`);
    }
  }

  async testGlobalStatsEndpoint() {
    console.log('\n📊 Testing Global Stats');
    
    const result = await this.makeRequest('GET', '/api/stats');
    
    if (result.success && result.data) {
      const metrics = Object.keys(result.data);
      this.log(true, 'GET /api/stats - Available', `${metrics.length} metrics: ${metrics.join(', ')}`);
    } else {
      this.log(false, 'GET /api/stats - Failed', `Status: ${result.status}, Error: ${result.data?.error || 'Unknown'}`);
    }
  }

  async testSkillLevelsEndpoint() {
    console.log('\n⚙️ Testing Skill Levels Configuration');
    
    const result = await this.makeRequest('GET', '/api/config/levels');
    
    if (result.success && result.data.config?.skillLevels) {
      const levels = result.data.config.skillLevels;
      this.log(true, 'GET /api/config/levels - Available', `${levels.length} skill levels configured`);
      
      // Check structure of first level
      if (levels.length > 0) {
        const firstLevel = levels[0];
        const hasRequiredFields = firstLevel.hasOwnProperty('level') && 
                                 firstLevel.hasOwnProperty('minScore') &&
                                 firstLevel.hasOwnProperty('title');
        
        if (hasRequiredFields) {
          this.log(true, 'Skill level structure valid', `Level ${firstLevel.level}: "${firstLevel.title}" (${firstLevel.minScore}+ points)`);
        } else {
          this.log(false, 'Skill level structure invalid', `Missing fields. Has: ${Object.keys(firstLevel).join(', ')}`);
        }
      }
    } else {
      this.log(false, 'GET /api/config/levels - Failed', `Status: ${result.status}, Error: ${result.data?.error || 'Unknown'}`);
    }
  }

  async testDifficultyAnalysis() {
    console.log('\n🔍 Testing Difficulty Analysis');
    
    const testCases = [
      { content: 'hello', expected: 'low difficulty' },
      { content: 'quick brown fox', expected: 'medium difficulty' },
      { content: 'the lazy dog jumps', expected: 'higher difficulty' }
    ];

    for (const testCase of testCases) {
      const result = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
        phrase: testCase.content,
        language: 'en'
      });

      if (result.success && typeof result.data.difficulty === 'number') {
        this.log(true, `Difficulty analysis: "${testCase.content}"`, `Difficulty: ${result.data.difficulty}`);
      } else {
        this.log(false, `Difficulty analysis: "${testCase.content}"`, `Status: ${result.status}, Error: ${result.data?.error || 'No difficulty score'}`);
      }
    }
  }

  async testContributionSystem() {
    console.log('\n🤝 Testing Contribution System');
    
    // Test with invalid token (should fail gracefully)
    const result = await this.makeRequest('POST', '/api/contribution/invalid-token/submit', {
      content: 'test contribution',
      language: 'en'
    });

    if (result.status === 400 || result.status === 404) {
      this.log(true, 'Contribution token validation', 'Correctly rejected invalid token');
    } else {
      this.log(false, 'Contribution token validation', `Status: ${result.status} (expected 400/404)`);
    }
  }

  async testAdminBatchImport() {
    console.log('\n🔐 Testing Admin Batch Import');
    
    // Test without API key (should fail)
    const unauthorizedResult = await this.makeRequest('POST', '/api/admin/phrases/batch-import', {
      phrases: [{ content: 'admin test', language: 'en' }]
    });

    if (unauthorizedResult.status === 401 || unauthorizedResult.status === 403) {
      this.log(true, 'Admin API key protection', 'Correctly rejected unauthorized access');
    } else {
      this.log(false, 'Admin API key protection', `Status: ${unauthorizedResult.status} (expected 401/403)`);
    }

    // Test with API key (if available in environment)
    const apiKey = process.env.ADMIN_API_KEY || 'test-admin-key-123';
    
    const authorizedResult = await this.makeRequest('POST', '/api/admin/phrases/batch-import', {
      phrases: [
        { content: 'batch test', language: 'en', hint: 'automated test phrase' }
      ]
    });

    // Manually add API key header by modifying the request
    const optionsWithKey = {
      hostname: HOST,
      port: PORT || 80,
      path: '/api/admin/phrases/batch-import',
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'X-API-Key': apiKey
      },
      timeout: 10000
    };

    const keyTestResult = await new Promise((resolve) => {
      const req = http.request(optionsWithKey, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            const parsed = body ? JSON.parse(body) : {};
            resolve({
              status: res.statusCode,
              data: parsed,
              success: res.statusCode >= 200 && res.statusCode < 300
            });
          } catch (e) {
            resolve({
              status: res.statusCode,
              data: body,
              success: false
            });
          }
        });
      });

      req.on('error', err => resolve({ success: false, error: err.message }));
      req.on('timeout', () => resolve({ success: false, error: 'Timeout' }));

      req.write(JSON.stringify({
        phrases: [{ content: 'api key test', language: 'en', hint: 'admin test' }]
      }));
      req.end();
    });

    if (keyTestResult.success) {
      this.log(true, 'Admin API with key', 'Batch import accepted with valid API key');
    } else {
      this.log(false, 'Admin API with key', `Status: ${keyTestResult.status}, Error: ${keyTestResult.data?.error || 'Unknown'}`);
    }
  }

  async testEdgeCasesAndValidation() {
    console.log('\n🎪 Testing Edge Cases');
    
    // Test malformed UUID
    const badUuidResult = await this.makeRequest('GET', '/api/phrases/for/not-a-uuid');
    if (badUuidResult.status === 400) {
      this.log(true, 'UUID validation', 'Correctly rejected malformed UUID');
    } else {
      this.log(false, 'UUID validation', `Status: ${badUuidResult.status} (expected 400)`);
    }
    
    // Test empty request body
    const emptyBodyResult = await this.makeRequest('POST', '/api/phrases/create', {});
    if (emptyBodyResult.status === 400) {
      this.log(true, 'Empty body validation', 'Correctly rejected empty request');
    } else {
      this.log(false, 'Empty body validation', `Status: ${emptyBodyResult.status} (expected 400)`);
    }
    
    // Test oversized content
    const oversizedResult = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
      phrase: 'word '.repeat(200), // Very long content
      language: 'en'
    });
    
    if (oversizedResult.status === 400) {
      this.log(true, 'Content size validation', 'Correctly rejected oversized content');
    } else {
      this.log(false, 'Content size validation', `Status: ${oversizedResult.status} (expected 400)`);
    }
  }

  async runAllTests() {
    console.log('🚀 Starting Additional Endpoints Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    await this.testLegendPlayersEndpoint();
    await this.testGlobalStatsEndpoint();
    await this.testSkillLevelsEndpoint();
    await this.testDifficultyAnalysis();
    await this.testContributionSystem();
    await this.testAdminBatchImport();
    await this.testEdgeCasesAndValidation();

    console.log('\n📊 ADDITIONAL ENDPOINTS TEST SUMMARY');
    console.log('='.repeat(50));
    console.log(`✅ Passed: ${this.passed}`);
    console.log(`❌ Failed: ${this.failed}`);
    console.log(`📊 Total: ${this.passed + this.failed}`);
    
    const successRate = this.failed === 0 ? 100 : ((this.passed / (this.passed + this.failed)) * 100).toFixed(1);
    console.log(`📈 Success Rate: ${successRate}%`);

    console.log(`\n🎯 Test completed at ${new Date().toISOString()}`);
    
    return this.failed === 0;
  }
}

// Run tests
if (require.main === module) {
  const tester = new AdditionalEndpointsTest();
  tester.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = AdditionalEndpointsTest;