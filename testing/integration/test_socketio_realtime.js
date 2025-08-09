#!/usr/bin/env node

/**
 * Socket.IO Real-time Testing Suite
 * Tests multiplayer functionality using Socket.IO client
 * 
 * Requires socket.io-client to be available in node_modules
 */

const http = require('http');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

// Try to require socket.io-client, fallback to manual testing if not available
let io;
try {
  io = require('socket.io-client');
} catch (e) {
  console.log('⚠️  socket.io-client not available, using manual HTTP-only tests');
}

console.log(`🌐 Testing Socket.IO Real-time Features`);
console.log(`📡 Server: ${API_URL}`);

class SocketIORealTimeTest {
  constructor() {
    this.passed = 0;
    this.failed = 0;
    this.testPlayers = [];
    this.sockets = [];
  }

  log(status, message, details = '') {
    const emoji = status ? '✅' : '❌';
    const timestamp = new Date().toISOString().substring(11, 23);
    console.log(`${emoji} [${timestamp}] ${message} ${details}`);
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

      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async setupTestPlayers() {
    console.log('\n🔧 Setting up test players');
    
    const timestamp = Date.now();
    const playerNames = [`SocketPlayer${timestamp}1`, `SocketPlayer${timestamp}2`];
    
    for (const name of playerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        language: 'en',
        deviceId: `socket-test-device-${Date.now()}-${Math.random()}`
      });
      
      if (result.success && result.data.success && result.data.player) {
        this.testPlayers.push(result.data.player);
        this.log(true, `Created test player: ${name}`, `ID: ${result.data.player.id}`);
      } else {
        this.log(false, `Failed to create player: ${name}`, `Error: ${result.data?.error || 'Unknown'}`);
      }
    }
  }

  async testSocketIOConnection() {
    if (!io) {
      this.log(false, 'Socket.IO client not available', 'Cannot test real-time features');
      return;
    }

    console.log('\n🔌 Testing Socket.IO Connection');
    
    return new Promise((resolve) => {
      const socket = io(API_URL, {
        transports: ['websocket', 'polling'],
        timeout: 10000
      });

      socket.on('connect', () => {
        this.log(true, 'Socket.IO connection established', `ID: ${socket.id}`);
        this.sockets.push(socket);
      });

      socket.on('welcome', (data) => {
        this.log(true, 'Welcome message received', `Message: ${data.message}`);
      });

      socket.on('connect_error', (error) => {
        this.log(false, 'Socket.IO connection failed', error.message);
        resolve();
      });

      socket.on('disconnect', (reason) => {
        this.log(true, 'Socket.IO disconnected', `Reason: ${reason}`);
      });

      // Test player connection event
      if (this.testPlayers.length > 0) {
        setTimeout(() => {
          socket.emit('player-connect', { playerId: this.testPlayers[0].id });
          this.log(true, 'Sent player-connect event', `Player: ${this.testPlayers[0].name}`);
        }, 2000);

        socket.on('player-connected', (data) => {
          this.log(true, 'Player connection confirmed', `Player: ${data.player?.name || 'Unknown'}`);
        });

        socket.on('player-list-updated', (data) => {
          this.log(true, 'Player list update received', `${data.players?.length || 0} players online`);
        });
      }

      // Clean up after 10 seconds
      setTimeout(() => {
        socket.disconnect();
        resolve();
      }, 10000);
    });
  }

  async testMultiplayerPhraseFlow() {
    if (!io || this.testPlayers.length < 2) {
      this.log(false, 'Multiplayer test skipped', 'Need Socket.IO client and 2+ players');
      return;
    }

    console.log('\n🎮 Testing Multiplayer Phrase Flow');
    
    return new Promise(async (resolve) => {
      // Create two socket connections
      const socket1 = io(API_URL, { transports: ['websocket', 'polling'] });
      const socket2 = io(API_URL, { transports: ['websocket', 'polling'] });
      
      let connectionsReady = 0;
      
      const checkReady = () => {
        connectionsReady++;
        if (connectionsReady === 2) {
          startTest();
        }
      };

      socket1.on('connect', () => {
        this.log(true, 'Player1 socket connected', `ID: ${socket1.id}`);
        socket1.emit('player-connect', { playerId: this.testPlayers[0].id });
        checkReady();
      });

      socket2.on('connect', () => {
        this.log(true, 'Player2 socket connected', `ID: ${socket2.id}`);
        socket2.emit('player-connect', { playerId: this.testPlayers[1].id });
        checkReady();
      });

      const startTest = async () => {
        // Wait a moment for connections to stabilize
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Create a phrase from player1 to player2
        const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
          content: 'socket test',
          language: 'en',
          senderId: this.testPlayers[0].id,
          targetId: this.testPlayers[1].id,
          hint: 'real-time test'
        });

        if (phraseResult.success) {
          this.log(true, 'Phrase created for real-time test', `ID: ${phraseResult.data.phrase.id}`);
          
          // Listen for new-phrase events
          socket2.on('new-phrase', (data) => {
            this.log(true, 'New phrase notification received', `Content: ${data.phrase?.content || 'Unknown'}`);
          });

        } else {
          this.log(false, 'Phrase creation failed', `Error: ${phraseResult.data?.error || 'Unknown'}`);
        }

        // Clean up after test
        setTimeout(() => {
          socket1.disconnect();
          socket2.disconnect();
          resolve();
        }, 8000);
      };

      // Handle connection errors
      socket1.on('connect_error', (error) => {
        this.log(false, 'Player1 connection failed', error.message);
        resolve();
      });

      socket2.on('connect_error', (error) => {
        this.log(false, 'Player2 connection failed', error.message);
        resolve();
      });
    });
  }

  async testWithoutSocketIOClient() {
    console.log('\n🔄 Testing Real-time Features (HTTP-only validation)');
    
    // Without Socket.IO client, we can at least test the HTTP endpoints
    // that support the real-time features
    
    if (this.testPlayers.length < 2) {
      this.log(false, 'HTTP validation skipped', 'Need at least 2 players');
      return;
    }

    // Test phrase creation (which triggers WebSocket events)
    const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: 'http test phrase',
      language: 'en',
      senderId: this.testPlayers[0].id,
      targetId: this.testPlayers[1].id,
      hint: 'http validation'
    });

    if (phraseResult.success && phraseResult.data.phrase) {
      this.log(true, 'Phrase creation (triggers WebSocket)', `ID: ${phraseResult.data.phrase.id}`);
      
      // Verify the phrase appears in target's queue
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait for processing
      
      const phrasesResult = await this.makeRequest('GET', `/api/phrases/for/${this.testPlayers[1].id}`);
      
      if (phrasesResult.success && phrasesResult.data.phrases?.length > 0) {
        const foundPhrase = phrasesResult.data.phrases.find(p => p.id === phraseResult.data.phrase.id);
        if (foundPhrase) {
          this.log(true, 'Phrase delivery confirmed', `Found in target's queue`);
        } else {
          this.log(false, 'Phrase delivery uncertain', 'Not found in target queue');
        }
      }
      
    } else {
      this.log(false, 'Phrase creation failed', `Error: ${phraseResult.data?.error || 'Unknown'}`);
    }

    // Test player online status (updated via WebSocket)
    const onlineResult = await this.makeRequest('GET', '/api/players/online');
    
    if (onlineResult.success && Array.isArray(onlineResult.data.players)) {
      const onlineCount = onlineResult.data.players.length;
      this.log(true, 'Player online status available', `${onlineCount} players currently online`);
    } else {
      this.log(false, 'Player online status unavailable', `Status: ${onlineResult.status}`);
    }
  }

  async cleanup() {
    console.log('\n🧹 Cleaning up connections');
    
    for (const socket of this.sockets) {
      if (socket && socket.connected) {
        socket.disconnect();
      }
    }
  }

  async runAllTests() {
    console.log('🚀 Starting Socket.IO Real-time Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.setupTestPlayers();
      
      if (io) {
        await this.testSocketIOConnection();
        await this.testMultiplayerPhraseFlow();
      } else {
        await this.testWithoutSocketIOClient();
      }
      
    } catch (error) {
      this.log(false, 'Test suite error', error.message);
    } finally {
      await this.cleanup();
    }

    console.log('\n📊 SOCKET.IO REAL-TIME TEST SUMMARY');
    console.log('='.repeat(50));
    console.log(`✅ Passed: ${this.passed}`);
    console.log(`❌ Failed: ${this.failed}`);
    console.log(`📊 Total: ${this.passed + this.failed}`);
    
    const successRate = this.failed === 0 ? 100 : ((this.passed / (this.passed + this.failed)) * 100).toFixed(1);
    console.log(`📈 Success Rate: ${successRate}%`);
    
    if (!io) {
      console.log('\n💡 To enable full WebSocket testing:');
      console.log('   cd services/game-server && npm install socket.io-client');
    }

    console.log(`\n🎯 Test completed at ${new Date().toISOString()}`);
    
    return this.failed === 0;
  }
}

// Run tests
if (require.main === module) {
  const tester = new SocketIORealTimeTest();
  tester.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = SocketIORealTimeTest;