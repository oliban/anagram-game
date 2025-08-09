#!/usr/bin/env node

/**
 * Simple API Test using built-in Node.js modules
 * Tests core endpoints to verify current functionality
 */

const http = require('http');
const https = require('https');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const BASE_HOST = API_URL.replace('http://', '').replace('https://', '');
const [HOST, PORT] = BASE_HOST.split(':');
const IS_HTTPS = API_URL.startsWith('https');

console.log(`🌐 Testing API: ${API_URL}`);

class SimpleAPITester {
  constructor() {
    this.passed = 0;
    this.failed = 0;
    this.testPlayers = [];
  }

  log(status, message, details = '') {
    const emoji = status ? '✅' : '❌';
    console.log(`${emoji} ${message} ${details}`);
    if (status) this.passed++; else this.failed++;
  }

  async makeRequest(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: HOST,
        port: PORT || (IS_HTTPS ? 443 : 80),
        path: path,
        method: method,
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 10000
      };

      const req = (IS_HTTPS ? https : http).request(options, (res) => {
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
              headers: res.headers,
              data: body,
              success: false,
              error: 'Invalid JSON response'
            });
          }
        });
      });

      req.on('error', err => reject(err));
      req.on('timeout', () => reject(new Error('Request timeout')));

      if (data) {
        req.write(JSON.stringify(data));
      }
      req.end();
    });
  }

  async testHealthCheck() {
    console.log('\n🔧 Testing System Health');
    
    try {
      const result = await this.makeRequest('GET', '/api/status');
      
      if (result.success && result.data.status === 'healthy') {
        this.log(true, 'Server health check', `Status: ${result.data.status}`);
      } else {
        this.log(false, 'Server health check', `Status: ${result.status}, Data: ${JSON.stringify(result.data)}`);
      }

      // Check rate limiting headers
      if (result.headers['ratelimit-limit']) {
        this.log(true, 'Rate limiting headers present', `Limit: ${result.headers['ratelimit-limit']}`);
      } else {
        this.log(false, 'Rate limiting headers missing');
      }
    } catch (error) {
      this.log(false, 'Server health check', `Error: ${error.message}`);
    }
  }

  async testPlayerRegistration() {
    console.log('\n👤 Testing Player Registration');
    
    const testNames = ['TestUser1', 'TestUser2'];
    
    for (const name of testNames) {
      try {
        const result = await this.makeRequest('POST', '/api/players/register', {
          name,
          language: 'en',
          deviceId: `test-device-${Date.now()}-${Math.random()}`
        });

        if (result.success && result.data.success && result.data.player) {
          this.testPlayers.push(result.data.player);
          this.log(true, `Player registration: ${name}`, `ID: ${result.data.player.id}`);
        } else {
          this.log(false, `Player registration: ${name}`, `Status: ${result.status}, Error: ${result.data?.error || 'Unknown'}`);
        }
      } catch (error) {
        this.log(false, `Player registration: ${name}`, `Error: ${error.message}`);
      }
    }

    // Test online players
    try {
      const result = await this.makeRequest('GET', '/api/players/online');
      
      if (result.success && Array.isArray(result.data.players)) {
        this.log(true, 'Get online players', `Found ${result.data.players.length} players`);
      } else {
        this.log(false, 'Get online players', `Status: ${result.status}`);
      }
    } catch (error) {
      this.log(false, 'Get online players', `Error: ${error.message}`);
    }
  }

  async testPhraseEndpoints() {
    console.log('\n📝 Testing Phrase Endpoints');
    
    if (this.testPlayers.length < 2) {
      this.log(false, 'Phrase tests skipped - need at least 2 players');
      return;
    }

    const sender = this.testPlayers[0];
    const target = this.testPlayers[1];

    // Test phrase creation
    try {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content: 'hello world',
        language: 'en',
        senderId: sender.id,
        targetId: target.id,
        hint: 'greeting'
      });

      if (result.success && result.data.success) {
        this.log(true, 'Phrase creation', `ID: ${result.data.phrase.id}`);
        
        // Test sender name functionality
        if (result.data.phrase.senderName && result.data.phrase.senderName !== 'Unknown Player') {
          this.log(true, 'Sender name lookup', `Sender: ${result.data.phrase.senderName}`);
        } else {
          this.log(false, 'Sender name lookup', `Got: ${result.data.phrase.senderName || 'null'}`);
        }

        // Test phrase retrieval
        const phrasesResult = await this.makeRequest('GET', `/api/phrases/for/${target.id}`);
        if (phrasesResult.success && Array.isArray(phrasesResult.data.phrases)) {
          this.log(true, 'Phrase retrieval', `Found ${phrasesResult.data.phrases.length} phrases`);
        } else {
          this.log(false, 'Phrase retrieval', `Status: ${phrasesResult.status}`);
        }

      } else {
        this.log(false, 'Phrase creation', `Status: ${result.status}, Error: ${result.data?.error || 'Unknown'}`);
      }
    } catch (error) {
      this.log(false, 'Phrase creation', `Error: ${error.message}`);
    }

    // Test invalid phrase (word too long)
    try {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content: 'verylongword test',
        language: 'en',
        senderId: sender.id,
        targetId: target.id
      });

      if (result.status === 400) {
        this.log(true, 'Word length validation', 'Correctly rejected long words');
      } else {
        this.log(false, 'Word length validation', `Status: ${result.status} (expected 400)`);
      }
    } catch (error) {
      this.log(false, 'Word length validation', `Error: ${error.message}`);
    }
  }

  async testLeaderboards() {
    console.log('\n🏆 Testing Leaderboards');
    
    try {
      const result = await this.makeRequest('GET', '/api/leaderboard/total');
      
      if (result.success && Array.isArray(result.data.leaderboard)) {
        this.log(true, 'Leaderboard retrieval', `Found ${result.data.leaderboard.length} entries`);
      } else {
        this.log(false, 'Leaderboard retrieval', `Status: ${result.status}`);
      }
    } catch (error) {
      this.log(false, 'Leaderboard retrieval', `Error: ${error.message}`);
    }
  }

  async testSecurityFeatures() {
    console.log('\n🛡️ Testing Security Features');
    
    // Test XSS prevention
    try {
      const result = await this.makeRequest('POST', '/api/phrases/create', {
        content: '<script>alert("xss")</script>',
        language: 'en',
        senderId: this.testPlayers[0]?.id || 'test',
        targetId: this.testPlayers[1]?.id || 'test'
      });

      if (result.status === 400) {
        this.log(true, 'XSS prevention', 'Malicious content rejected');
      } else {
        this.log(false, 'XSS prevention', `Status: ${result.status} (expected 400)`);
      }
    } catch (error) {
      this.log(false, 'XSS prevention', `Error: ${error.message}`);
    }

    // Test SQL injection prevention
    try {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name: "test'; DROP TABLE players; --",
        language: 'en',
        deviceId: 'test-device-sql-injection'
      });

      if (result.status === 400) {
        this.log(true, 'SQL injection prevention', 'Malicious SQL rejected');
      } else {
        this.log(false, 'SQL injection prevention', `Status: ${result.status} (expected 400)`);
      }
    } catch (error) {
      this.log(false, 'SQL injection prevention', `Error: ${error.message}`);
    }
  }

  async runAllTests() {
    console.log('🚀 Starting Simple API Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    await this.testHealthCheck();
    await this.testPlayerRegistration();
    await this.testPhraseEndpoints();
    await this.testLeaderboards();
    await this.testSecurityFeatures();

    console.log('\n📊 TEST SUMMARY');
    console.log('='.repeat(40));
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
  const tester = new SimpleAPITester();
  tester.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = SimpleAPITester;