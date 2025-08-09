#!/usr/bin/env node

/**
 * Missing Endpoints API Test Suite
 * Tests all previously untested endpoints and edge cases
 */

const http = require('http');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🧪 Testing Missing Endpoints: ${API_URL}`);

class MissingEndpointsTest {
  constructor() {
    this.passed = 0;
    this.failed = 0;
    this.testPlayers = [];
    this.testPhrases = [];
  }

  log(status, message, details = '') {
    const emoji = status ? '✅' : '❌';
    console.log(`${emoji} ${message} ${details}`);
    if (status) this.passed++; else this.failed++;
  }

  async makeRequest(method, path, data = null, expectedStatus = 200) {
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
              success: res.statusCode === expectedStatus
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

  async setupTestData() {
    console.log('\n🔧 Setting up test data');
    
    // Create test players
    const names = ['TestPlayerA', 'TestPlayerB'];
    for (const name of names) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        language: 'en',
        deviceId: `test-device-${Date.now()}-${Math.random()}`
      });
      
      if (result.success && result.data.success && result.data.player) {
        this.testPlayers.push(result.data.player);
        this.log(true, `Setup player: ${name}`, `ID: ${result.data.player.id}`);
      } else {
        this.log(false, `Setup player: ${name}`, `Status: ${result.status}, Error: ${result.data?.error}`);
      }
    }

    // Create test phrases
    if (this.testPlayers.length >= 2) {
      const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
        content: 'test phrase',
        language: 'en',
        senderId: this.testPlayers[0].id,
        targetId: this.testPlayers[1].id,
        hint: 'test'
      });

      if (phraseResult.success && phraseResult.data.success && phraseResult.data.phrase) {
        this.testPhrases.push(phraseResult.data.phrase);
        this.log(true, 'Setup phrase', `ID: ${phraseResult.data.phrase.id}`);
      } else {
        this.log(false, 'Setup phrase', `Status: ${phraseResult.status}, Error: ${phraseResult.data?.error}`);
      }
    }
  }

  async testLegendPlayers() {
    console.log('\n🏆 Testing Legend Players');
    
    const result = await this.makeRequest('GET', '/api/players/legends');
    
    if (result.success && Array.isArray(result.data.legends)) {
      this.log(true, 'GET /api/players/legends', `Found ${result.data.legends.length} legends`);
    } else {
      this.log(false, 'GET /api/players/legends', `Status: ${result.status}, Error: ${result.data?.error}`);
    }
  }

  async testGlobalStats() {
    console.log('\n📊 Testing Global Statistics');
    
    const result = await this.makeRequest('GET', '/api/stats');
    
    if (result.success && result.data) {
      this.log(true, 'GET /api/stats', `Stats: ${Object.keys(result.data).length} metrics`);
    } else {
      this.log(false, 'GET /api/stats', `Status: ${result.status}, Error: ${result.data?.error}`);
    }
  }

  async testSkillLevelConfig() {
    console.log('\n⚙️ Testing Skill Level Configuration');
    
    const result = await this.makeRequest('GET', '/api/config/levels');
    
    if (result.success && result.data.config?.skillLevels) {
      const levelCount = result.data.config.skillLevels.length;
      this.log(true, 'GET /api/config/levels', `Found ${levelCount} skill levels`);
      
      // Validate skill level structure
      const firstLevel = result.data.config.skillLevels[0];
      if (firstLevel && typeof firstLevel.level === 'number' && typeof firstLevel.minScore === 'number') {
        this.log(true, 'Skill level data structure valid', `Level ${firstLevel.level}: ${firstLevel.minScore} min score`);
      } else {
        this.log(false, 'Skill level data structure invalid', 'Missing level or minScore fields');
      }
    } else {
      this.log(false, 'GET /api/config/levels', `Status: ${result.status}, Error: ${result.data?.error}`);
    }
  }

  async testPhraseCompletion() {
    console.log('\n✅ Testing Phrase Completion');
    
    if (this.testPhrases.length === 0) {
      this.log(false, 'Phrase completion tests skipped - no test phrases available');
      return;
    }

    const phraseId = this.testPhrases[0].id;
    const playerId = this.testPlayers[1].id;

    // Test successful completion
    const result = await this.makeRequest('POST', `/api/phrases/${phraseId}/complete`, {
      playerId: playerId,
      hintsUsed: 0,
      completionTime: 5000,
      celebrationEmojis: ['🎉', '✨', '🏆']
    });

    if (result.success) {
      this.log(true, 'POST /api/phrases/:phraseId/complete', `Phrase ${phraseId} completed`);
      
      // Check if scoring data is returned
      if (result.data.completion && typeof result.data.completion.scoreAwarded === 'number') {
        this.log(true, 'Scoring system functional', `Awarded ${result.data.completion.scoreAwarded} points`);
      } else {
        this.log(false, 'Scoring system issue', 'No score awarded or invalid response structure');
      }
    } else {
      this.log(false, 'POST /api/phrases/:phraseId/complete', `Status: ${result.status}, Error: ${result.data?.error}`);
    }

    // Test invalid completion (missing required fields)
    const invalidResult = await this.makeRequest('POST', `/api/phrases/${phraseId}/complete`, {
      playerId: playerId
      // Missing hintsUsed and completionTime
    }, 400);

    if (invalidResult.status === 400) {
      this.log(true, 'Phrase completion validation', 'Correctly rejected incomplete data');
    } else {
      this.log(false, 'Phrase completion validation', `Status: ${invalidResult.status} (expected 400)`);
    }
  }

  async testPhraseConsumption() {
    console.log('\n📥 Testing Phrase Consumption');
    
    if (this.testPhrases.length === 0) {
      this.log(false, 'Phrase consumption tests skipped - no test phrases available');
      return;
    }

    // Create a new phrase for consumption testing
    const consumeResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'consume test',
      language: 'en', 
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'consumption'
    });

    if (consumeResult.success) {
      const phraseId = consumeResult.data.phrase.id;
      
      const result = await this.makeRequest('POST', `/api/phrases/${phraseId}/consume`);
      
      if (result.success) {
        this.log(true, 'POST /api/phrases/:phraseId/consume', `Phrase ${phraseId} consumed`);
      } else {
        this.log(false, 'POST /api/phrases/:phraseId/consume', `Status: ${result.status}, Error: ${result.data?.error}`);
      }
    } else {
      this.log(false, 'Setup for consumption test failed', `Could not create test phrase`);
    }
  }

  async testPhraseSkipping() {
    console.log('\n⏭️ Testing Phrase Skipping');
    
    // Create a phrase specifically for skipping
    const skipResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'skip test',
      language: 'en',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'skip this'
    });

    if (skipResult.success && skipResult.data.success && this.testPlayers.length >= 2) {
      const phraseId = skipResult.data.phrase.id;
      const playerId = this.testPlayers[1].id;
      
      const result = await this.makeRequest('POST', `/api/phrases/${phraseId}/skip`, {
        playerId: playerId
      });
      
      if (result.success) {
        this.log(true, 'POST /api/phrases/:phraseId/skip', `Phrase ${phraseId} skipped`);
      } else {
        this.log(false, 'POST /api/phrases/:phraseId/skip', `Status: ${result.status}, Error: ${result.data?.error}`);
      }
    } else {
      this.log(false, 'Setup for skip test failed', 'Could not create test phrase');
    }
  }

  async testDifficultyAnalysis() {
    console.log('\n🔍 Testing Difficulty Analysis');
    
    const testPhrases = [
      'hello world',
      'quick brown fox',
      'very complex sentence structure'
    ];

    for (const content of testPhrases) {
      const result = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
        content: content,
        language: 'en'
      });

      if (result.success && typeof result.data.difficulty === 'number') {
        this.log(true, `Difficulty analysis: "${content}"`, `Difficulty: ${result.data.difficulty}`);
      } else {
        this.log(false, `Difficulty analysis: "${content}"`, `Status: ${result.status}, Error: ${result.data?.error}`);
      }
    }
  }

  async testPlayerSpecificLeaderboard() {
    console.log('\n🎯 Testing Player-Specific Leaderboards');
    
    if (this.testPlayers.length === 0) {
      this.log(false, 'Player leaderboard tests skipped - no test players available');
      return;
    }

    const playerId = this.testPlayers[0].id;
    const types = ['daily', 'weekly', 'total'];
    
    for (const type of types) {
      const result = await this.makeRequest('GET', `/api/leaderboard/${type}/player/${playerId}`);
      
      if (result.success) {
        this.log(true, `GET /api/leaderboard/${type}/player/:playerId`, `Player position retrieved`);
      } else {
        this.log(false, `GET /api/leaderboard/${type}/player/:playerId`, `Status: ${result.status}, Error: ${result.data?.error}`);
      }
    }
  }

  async testPlayerScores() {
    console.log('\n💯 Testing Player Score Details');
    
    if (this.testPlayers.length === 0) {
      this.log(false, 'Player score tests skipped - no test players available');
      return;
    }

    const playerId = this.testPlayers[0].id;
    const result = await this.makeRequest('GET', `/api/scores/player/${playerId}`);
    
    if (result.success && result.data.playerScores) {
      this.log(true, 'GET /api/scores/player/:playerId', `Score data retrieved`);
      
      // Check emoji collection functionality
      if (result.data.rarestEmojis && Array.isArray(result.data.rarestEmojis)) {
        const emojiCount = result.data.rarestEmojis.length;
        this.log(true, 'Emoji collection system', `Found ${emojiCount} emojis (max 16)`);
        
        if (emojiCount <= 16) {
          this.log(true, 'Emoji collection limit enforced', `Correctly limited to ${emojiCount}/16`);
        } else {
          this.log(false, 'Emoji collection limit issue', `Found ${emojiCount} emojis (should be ≤16)`);
        }
      }
    } else {
      this.log(false, 'GET /api/scores/player/:playerId', `Status: ${result.status}, Error: ${result.data?.error}`);
    }
  }

  async testPerformanceMetrics() {
    console.log('\n📈 Testing Performance Metrics');
    
    const result = await this.makeRequest('POST', '/api/debug/performance', {
      metric: 'api_test_performance',
      value: 95.5,
      category: 'test',
      playerId: this.testPlayers[0]?.id
    });

    if (result.success) {
      this.log(true, 'POST /api/debug/performance', 'Performance metric submitted');
    } else {
      this.log(false, 'POST /api/debug/performance', `Status: ${result.status}, Error: ${result.data?.error}`);
    }
  }

  async testEdgeCases() {
    console.log('\n🎪 Testing Edge Cases');
    
    // Test invalid UUID format
    const invalidUuidResult = await this.makeRequest('GET', '/api/phrases/for/invalid-uuid-format', null, 400);
    if (invalidUuidResult.status === 400) {
      this.log(true, 'Invalid UUID handling', 'Correctly rejected malformed UUID');
    } else {
      this.log(false, 'Invalid UUID handling', `Status: ${invalidUuidResult.status} (expected 400)`);
    }
    
    // Test empty JSON payload
    const emptyPayloadResult = await this.makeRequest('POST', '/api/phrases/create', {}, 400);
    if (emptyPayloadResult.status === 400) {
      this.log(true, 'Empty payload handling', 'Correctly rejected empty data');
    } else {
      this.log(false, 'Empty payload handling', `Status: ${emptyPayloadResult.status} (expected 400)`);
    }
    
    // Test very long strings
    const longStringResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'a'.repeat(1000),
      language: 'en',
      senderId: this.testPlayers[0]?.id || 'test',
      targetId: this.testPlayers[1]?.id || 'test'
    }, 400);
    
    if (longStringResult.status === 400) {
      this.log(true, 'String length validation', 'Correctly rejected oversized content');
    } else {
      this.log(false, 'String length validation', `Status: ${longStringResult.status} (expected 400)`);
    }
  }

  async runAllTests() {
    console.log('🚀 Starting Missing Endpoints Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    await this.setupTestData();
    await this.testLegendPlayers();
    await this.testGlobalStats();
    await this.testSkillLevelConfig();
    await this.testPhraseCompletion();
    await this.testPhraseConsumption();
    await this.testPhraseSkipping();
    await this.testDifficultyAnalysis();
    await this.testPlayerSpecificLeaderboard();
    await this.testPlayerScores();
    await this.testPerformanceMetrics();
    await this.testEdgeCases();

    console.log('\n📊 MISSING ENDPOINTS TEST SUMMARY');
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
  const tester = new MissingEndpointsTest();
  tester.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = MissingEndpointsTest;