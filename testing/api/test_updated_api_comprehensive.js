#!/usr/bin/env node

/**
 * UPDATED Comprehensive API Test Suite
 * 
 * Tests ALL current API endpoints with proper validation and current requirements
 * Updated for Wordshelf v2.0 with microservices architecture
 * 
 * Usage: API_URL=http://192.168.1.188:3000 node test_updated_api_comprehensive.js
 */

const axios = require('axios');
const { io } = require('socket.io-client');

// Environment-aware configuration
const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const WS_URL = API_URL.replace('http://', 'ws://').replace('https://', 'wss://');

console.log(`🌐 Testing API: ${API_URL}`);
console.log(`🔌 Testing WebSocket: ${WS_URL}`);

class ComprehensiveAPITester {
  constructor() {
    this.results = { passed: 0, failed: 0, skipped: 0, details: [] };
    this.testPlayers = [];
    this.testPhrases = [];
  }

  async log(level, message, details = null) {
    const timestamp = new Date().toISOString();
    const emoji = level === 'pass' ? '✅' : level === 'fail' ? '❌' : level === 'skip' ? '⏭️' : 'ℹ️';
    console.log(`${emoji} [${timestamp}] ${message}`);
    if (details) console.log(`   📋 ${details}`);
    
    this.results.details.push({ level, message, details, timestamp });
    if (level === 'pass') this.results.passed++;
    else if (level === 'fail') this.results.failed++;
    else if (level === 'skip') this.results.skipped++;
  }

  async makeRequest(method, path, data = null, expectedStatus = 200, headers = {}) {
    try {
      const config = {
        method,
        url: `${API_URL}${path}`,
        headers: { 'Content-Type': 'application/json', ...headers },
        timeout: 10000,
        validateStatus: () => true // Don't throw on non-2xx status
      };
      
      if (data) config.data = data;
      
      const response = await axios(config);
      return {
        success: response.status === expectedStatus,
        status: response.status,
        data: response.data,
        headers: response.headers
      };
    } catch (error) {
      return {
        success: false,
        error: error.message,
        status: error.response?.status || 0
      };
    }
  }

  // Test System Endpoints
  async testSystemEndpoints() {
    await this.log('info', '🔧 Testing System Endpoints');

    // Test server health
    const statusResult = await this.makeRequest('GET', '/api/status');
    if (statusResult.success && statusResult.data.status === 'healthy') {
      await this.log('pass', 'GET /api/status - Server health check', `Status: ${statusResult.data.status}`);
    } else {
      await this.log('fail', 'GET /api/status - Server health check', `Error: ${statusResult.error || statusResult.status}`);
    }

    // Test level configuration
    const levelsResult = await this.makeRequest('GET', '/api/config/levels');
    if (levelsResult.success && levelsResult.data.config?.skillLevels) {
      const levelCount = levelsResult.data.config.skillLevels.length;
      await this.log('pass', 'GET /api/config/levels - Level configuration', `Found ${levelCount} skill levels`);
    } else {
      await this.log('fail', 'GET /api/config/levels - Level configuration', `Error: ${levelsResult.error || levelsResult.status}`);
    }

    // Test rate limiting headers
    if (statusResult.headers['ratelimit-limit']) {
      await this.log('pass', 'Rate limiting headers present', `Limit: ${statusResult.headers['ratelimit-limit']}`);
    } else {
      await this.log('fail', 'Rate limiting headers missing', 'No RateLimit-* headers found');
    }
  }

  // Test Player Management
  async testPlayerEndpoints() {
    await this.log('info', '👤 Testing Player Management Endpoints');

    // Valid player registration
    const validNames = ['TestUser1', 'TestUser2', 'AliceTest', 'BobTest'];
    for (const name of validNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        language: 'en'
      });

      if (result.success && result.data.success && result.data.player) {
        this.testPlayers.push(result.data.player);
        await this.log('pass', `POST /api/players/register - Valid registration`, `Player: ${name} (${result.data.player.id})`);
      } else {
        await this.log('fail', `POST /api/players/register - Valid registration`, `Failed for ${name}: ${result.error || result.data?.error}`);
      }
    }

    // Invalid player registration tests
    const invalidCases = [
      { case: 'empty name', data: { name: '', language: 'en' } },
      { case: 'missing name', data: { language: 'en' } },
      { case: 'invalid language', data: { name: 'Test', language: 'fr' } },
      { case: 'name too long', data: { name: 'a'.repeat(100), language: 'en' } },
      { case: 'invalid characters', data: { name: 'Test🤖Invalid', language: 'en' } }
    ];

    for (const { case: testCase, data } of invalidCases) {
      const result = await this.makeRequest('POST', '/api/players/register', data, 400);
      if (result.status === 400) {
        await this.log('pass', `POST /api/players/register - Invalid: ${testCase}`, 'Correctly rejected');
      } else {
        await this.log('fail', `POST /api/players/register - Invalid: ${testCase}`, `Unexpected status: ${result.status}`);
      }
    }

    // Get online players
    const onlineResult = await this.makeRequest('GET', '/api/players/online');
    if (onlineResult.success && Array.isArray(onlineResult.data.players)) {
      await this.log('pass', 'GET /api/players/online - Retrieve online players', `Found ${onlineResult.data.players.length} players`);
    } else {
      await this.log('fail', 'GET /api/players/online - Retrieve online players', `Error: ${onlineResult.error || onlineResult.status}`);
    }

    // Test player scores endpoint
    if (this.testPlayers.length > 0) {
      const playerId = this.testPlayers[0].id;
      const scoresResult = await this.makeRequest('GET', `/api/scores/player/${playerId}`);
      if (scoresResult.success) {
        await this.log('pass', 'GET /api/scores/player/{playerId} - Player scores', `Player: ${playerId}`);
      } else {
        await this.log('fail', 'GET /api/scores/player/{playerId} - Player scores', `Error: ${scoresResult.error || scoresResult.status}`);
      }
    }
  }

  // Test Phrase Management
  async testPhraseEndpoints() {
    await this.log('info', '📝 Testing Phrase Management Endpoints');

    if (this.testPlayers.length < 2) {
      await this.log('skip', 'Phrase tests skipped - need at least 2 players', 'Register more players first');
      return;
    }

    const sender = this.testPlayers[0];
    const target = this.testPlayers[1];

    // Valid phrase creation tests
    const validPhrases = [
      'hello world',
      'quick brown', 
      'test ok',
      'game fun'
    ];

    for (const content of validPhrases) {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content,
        language: 'en',
        senderId: sender.id,
        targetId: target.id,
        hint: 'test hint'
      });

      if (result.success && result.data.success && result.data.phrase) {
        this.testPhrases.push(result.data.phrase);
        await this.log('pass', 'POST /api/phrases/create - Valid phrase', `Content: "${content}" (ID: ${result.data.phrase.id})`);
        
        // Check sender name is populated
        if (result.data.phrase.senderName && result.data.phrase.senderName !== 'Unknown Player') {
          await this.log('pass', 'Sender name lookup working', `Sender: ${result.data.phrase.senderName}`);
        } else {
          await this.log('fail', 'Sender name lookup failed', `Got: ${result.data.phrase.senderName || 'null'}`);
        }
      } else {
        await this.log('fail', 'POST /api/phrases/create - Valid phrase', `Failed for "${content}": ${result.error || result.data?.error}`);
      }
    }

    // Invalid phrase creation tests
    const invalidPhrases = [
      { case: 'missing content', data: { language: 'en', senderId: sender.id, targetId: target.id } },
      { case: 'empty content', data: { content: '', language: 'en', senderId: sender.id, targetId: target.id } },
      { case: 'missing language', data: { content: 'test phrase', senderId: sender.id, targetId: target.id } },
      { case: 'invalid language', data: { content: 'test phrase', language: 'fr', senderId: sender.id, targetId: target.id } },
      { case: 'word too long', data: { content: 'verylongword test', language: 'en', senderId: sender.id, targetId: target.id } },
      { case: 'invalid characters', data: { content: 'test <script>alert("xss")</script>', language: 'en', senderId: sender.id, targetId: target.id } }
    ];

    for (const { case: testCase, data } of invalidPhrases) {
      const result = await this.makeRequest('POST', '/api/phrases/create', data, 400);
      if (result.status === 400) {
        await this.log('pass', `POST /api/phrases/create - Invalid: ${testCase}`, 'Correctly rejected');
      } else {
        await this.log('fail', `POST /api/phrases/create - Invalid: ${testCase}`, `Unexpected status: ${result.status}`);
      }
    }

    // Test phrase retrieval
    const phrasesResult = await this.makeRequest('GET', `/api/phrases/for/${target.id}`);
    if (phrasesResult.success && Array.isArray(phrasesResult.data.phrases)) {
      await this.log('pass', 'GET /api/phrases/for/{playerId} - Phrase retrieval', `Found ${phrasesResult.data.phrases.length} phrases for target`);
    } else {
      await this.log('fail', 'GET /api/phrases/for/{playerId} - Phrase retrieval', `Error: ${phrasesResult.error || phrasesResult.status}`);
    }

    // Test phrase completion
    if (this.testPhrases.length > 0) {
      const phraseId = this.testPhrases[0].id;
      const completionResult = await this.makeRequest('POST', `/api/phrases/${phraseId}/complete`, {
        playerId: target.id,
        hintsUsed: 0,
        completionTime: 5000,
        celebrationEmojis: ['🎉', '✨']
      });

      if (completionResult.success) {
        await this.log('pass', 'POST /api/phrases/{phraseId}/complete - Phrase completion', `Phrase ID: ${phraseId}`);
      } else {
        await this.log('fail', 'POST /api/phrases/{phraseId}/complete - Phrase completion', `Error: ${completionResult.error || completionResult.status}`);
      }

      // Test phrase skip
      if (this.testPhrases.length > 1) {
        const skipPhraseId = this.testPhrases[1].id;
        const skipResult = await this.makeRequest('POST', `/api/phrases/${skipPhraseId}/skip`, {
          playerId: target.id
        });

        if (skipResult.success) {
          await this.log('pass', 'POST /api/phrases/{phraseId}/skip - Phrase skip', `Phrase ID: ${skipPhraseId}`);
        } else {
          await this.log('fail', 'POST /api/phrases/{phraseId}/skip - Phrase skip', `Error: ${skipResult.error || skipResult.status}`);
        }
      }
    }
  }

  // Test Leaderboard Endpoints
  async testLeaderboardEndpoints() {
    await this.log('info', '🏆 Testing Leaderboard Endpoints');

    const periods = ['daily', 'weekly', 'monthly', 'legends'];
    for (const period of periods) {
      const result = await this.makeRequest('GET', `/api/leaderboard/${period}`);
      if (result.success && result.data.leaderboard) {
        await this.log('pass', `GET /api/leaderboard/${period} - Leaderboard retrieval`, `Found ${result.data.leaderboard.length} entries`);
      } else {
        await this.log('fail', `GET /api/leaderboard/${period} - Leaderboard retrieval`, `Error: ${result.error || result.status}`);
      }
    }

    // Test leaderboard with query parameters
    const limitResult = await this.makeRequest('GET', '/api/leaderboard/legends?limit=5&offset=0');
    if (limitResult.success) {
      await this.log('pass', 'GET /api/leaderboard with query params - Pagination', 'Limit and offset working');
    } else {
      await this.log('fail', 'GET /api/leaderboard with query params - Pagination', `Error: ${limitResult.error || limitResult.status}`);
    }
  }

  // Test Debug Endpoints  
  async testDebugEndpoints() {
    await this.log('info', '🐛 Testing Debug Endpoints');

    const debugResult = await this.makeRequest('POST', '/api/debug/log', {
      level: 'info',
      message: 'Test debug log from API test suite',
      playerId: this.testPlayers[0]?.id
    });

    if (debugResult.success) {
      await this.log('pass', 'POST /api/debug/log - Debug log submission', 'Debug log accepted');
    } else {
      await this.log('fail', 'POST /api/debug/log - Debug log submission', `Error: ${debugResult.error || debugResult.status}`);
    }

    // Test performance endpoint
    const perfResult = await this.makeRequest('POST', '/api/debug/performance', {
      metric: 'api_test',
      value: 100,
      playerId: this.testPlayers[0]?.id
    });

    if (perfResult.success) {
      await this.log('pass', 'POST /api/debug/performance - Performance metric', 'Performance data accepted');
    } else {
      await this.log('fail', 'POST /api/debug/performance - Performance metric', `Error: ${perfResult.error || perfResult.status}`);
    }
  }

  // Test Admin Endpoints (requires API key)
  async testAdminEndpoints() {
    await this.log('info', '🔐 Testing Admin Endpoints');

    // Test without API key (should fail)
    const unauthorizedResult = await this.makeRequest('POST', '/api/admin/phrases/batch-import', {
      phrases: [{ content: 'test admin', language: 'en' }]
    }, 401);

    if (unauthorizedResult.status === 401) {
      await this.log('pass', 'POST /api/admin/phrases/batch-import - Unauthorized access', 'Correctly rejected without API key');
    } else {
      await this.log('fail', 'POST /api/admin/phrases/batch-import - Unauthorized access', `Unexpected status: ${unauthorizedResult.status}`);
    }

    // Test with API key (if available)
    const apiKey = process.env.ADMIN_API_KEY || 'test-admin-key-123';
    const authorizedResult = await this.makeRequest('POST', '/api/admin/phrases/batch-import', {
      phrases: [{ content: 'test admin', language: 'en', hint: 'admin test' }]
    }, 200, { 'X-API-Key': apiKey });

    if (authorizedResult.success) {
      await this.log('pass', 'POST /api/admin/phrases/batch-import - Authorized access', 'Batch import successful');
    } else {
      await this.log('fail', 'POST /api/admin/phrases/batch-import - Authorized access', `Error: ${authorizedResult.error || authorizedResult.status}`);
    }
  }

  // Test WebSocket Functionality
  async testWebSocketEndpoints() {
    await this.log('info', '🔌 Testing WebSocket Functionality');

    return new Promise((resolve) => {
      let testsCompleted = 0;
      const totalTests = 3;

      // Test main game WebSocket namespace
      const gameSocket = io(WS_URL, {
        transports: ['websocket'],
        timeout: 5000
      });

      gameSocket.on('connect', async () => {
        await this.log('pass', 'WebSocket connection - Game namespace', 'Connected successfully');
        testsCompleted++;
        if (testsCompleted >= totalTests) resolve();
      });

      gameSocket.on('connect_error', async (error) => {
        await this.log('fail', 'WebSocket connection - Game namespace', `Connection failed: ${error.message}`);
        testsCompleted++;
        if (testsCompleted >= totalTests) resolve();
      });

      gameSocket.on('welcome', async (data) => {
        await this.log('pass', 'WebSocket welcome message', `Received: ${data.message}`);
        testsCompleted++;
        if (testsCompleted >= totalTests) resolve();
      });

      // Test player connection
      if (this.testPlayers.length > 0) {
        setTimeout(() => {
          gameSocket.emit('player-connect', { playerId: this.testPlayers[0].id });
        }, 1000);

        gameSocket.on('player-connected', async (data) => {
          await this.log('pass', 'WebSocket player connection', `Player connected: ${data.player.name}`);
          testsCompleted++;
          if (testsCompleted >= totalTests) resolve();
        });
      } else {
        testsCompleted++;
        if (testsCompleted >= totalTests) resolve();
      }

      // Timeout after 10 seconds
      setTimeout(() => {
        gameSocket.disconnect();
        if (testsCompleted < totalTests) {
          this.log('fail', 'WebSocket tests timeout', 'Tests did not complete within 10 seconds');
        }
        resolve();
      }, 10000);
    });
  }

  // Test Security Features
  async testSecurityFeatures() {
    await this.log('info', '🛡️ Testing Security Features');

    // Test CORS headers
    const corsResult = await this.makeRequest('GET', '/api/status');
    if (corsResult.headers['access-control-allow-origin']) {
      await this.log('pass', 'CORS headers present', `Origin: ${corsResult.headers['access-control-allow-origin']}`);
    } else {
      await this.log('fail', 'CORS headers missing', 'No Access-Control-Allow-Origin header');
    }

    // Test XSS prevention
    const xssResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: '<script>alert("xss")</script>',
      language: 'en',
      senderId: this.testPlayers[0]?.id || 'test-id',
      targetId: this.testPlayers[1]?.id || 'test-id'
    }, 400);

    if (xssResult.status === 400) {
      await this.log('pass', 'XSS prevention active', 'Malicious content rejected');
    } else {
      await this.log('fail', 'XSS prevention failed', `Status: ${xssResult.status}`);
    }

    // Test SQL injection prevention  
    const sqlResult = await this.makeRequest('POST', '/api/players/register', {
      name: "test'; DROP TABLE players; --",
      language: 'en'
    }, 400);

    if (sqlResult.status === 400) {
      await this.log('pass', 'SQL injection prevention active', 'Malicious SQL rejected');
    } else {
      await this.log('fail', 'SQL injection prevention failed', `Status: ${sqlResult.status}`);
    }
  }

  // Run all tests
  async runAllTests() {
    console.log(`🚀 Starting Comprehensive API Test Suite`);
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.testSystemEndpoints();
      await this.testPlayerEndpoints();
      await this.testPhraseEndpoints();
      await this.testLeaderboardEndpoints();
      await this.testDebugEndpoints();
      await this.testAdminEndpoints();
      await this.testWebSocketEndpoints();
      await this.testSecurityFeatures();

      // Print summary
      console.log('\n📊 TEST SUMMARY');
      console.log('=' .repeat(50));
      console.log(`✅ Passed: ${this.results.passed}`);
      console.log(`❌ Failed: ${this.results.failed}`);
      console.log(`⏭️ Skipped: ${this.results.skipped}`);
      console.log(`📊 Total: ${this.results.passed + this.results.failed + this.results.skipped}`);
      
      const successRate = ((this.results.passed / (this.results.passed + this.results.failed)) * 100).toFixed(1);
      console.log(`📈 Success Rate: ${successRate}%`);

      if (this.results.failed > 0) {
        console.log('\n❌ FAILED TESTS:');
        this.results.details
          .filter(r => r.level === 'fail')
          .forEach(r => console.log(`   • ${r.message}: ${r.details}`));
      }

      console.log(`\n🎯 Test completed at ${new Date().toISOString()}`);
      
      // Exit with proper code
      process.exit(this.results.failed > 0 ? 1 : 0);

    } catch (error) {
      console.error('💥 Test suite crashed:', error);
      process.exit(1);
    }
  }
}

// Run tests
if (require.main === module) {
  const tester = new ComprehensiveAPITester();
  tester.runAllTests();
}

module.exports = ComprehensiveAPITester;