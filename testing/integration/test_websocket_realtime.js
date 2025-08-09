#!/usr/bin/env node

/**
 * WebSocket Real-time Testing Suite
 * Tests multiplayer functionality, real-time events, and WebSocket communication
 * 
 * This test simulates real multiplayer scenarios:
 * - Player connections and disconnections
 * - Real-time phrase delivery
 * - Player list updates
 * - Multiplayer notifications
 */

const http = require('http');
const WebSocket = require('ws');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const WS_URL = API_URL.replace('http://', 'ws://');
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🌐 Testing WebSocket Real-time Features`);
console.log(`📡 HTTP API: ${API_URL}`);
console.log(`🔌 WebSocket: ${WS_URL}`);

class WebSocketRealTimeTest {
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

  async createWebSocketConnection(name) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(WS_URL, {
        handshakeTimeout: 5000
      });

      const connection = {
        name,
        ws,
        events: [],
        connected: false
      };

      ws.on('open', () => {
        connection.connected = true;
        this.log(true, `WebSocket connection established`, `${name}`);
        resolve(connection);
      });

      ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          connection.events.push({
            type: message.type || 'message',
            data: message,
            timestamp: new Date().toISOString()
          });
          
          // Log important events
          if (['welcome', 'player-connected', 'player-list-updated', 'new-phrase'].includes(message.type)) {
            this.log(true, `${name} received: ${message.type}`, JSON.stringify(message).substring(0, 100) + '...');
          }
        } catch (e) {
          this.log(false, `${name} received invalid JSON`, data.toString());
        }
      });

      ws.on('error', (error) => {
        this.log(false, `${name} WebSocket error`, error.message);
        reject(error);
      });

      ws.on('close', () => {
        connection.connected = false;
        this.log(true, `${name} WebSocket closed`, 'Connection terminated');
      });

      // Timeout if connection doesn't establish
      setTimeout(() => {
        if (!connection.connected) {
          reject(new Error(`${name} connection timeout`));
        }
      }, 10000);
    });
  }

  async setupTestPlayers() {
    console.log('\n🔧 Setting up test players');
    
    const playerNames = ['WSPlayer1', 'WSPlayer2', 'WSPlayer3'];
    
    for (const name of playerNames) {
      const result = await this.makeRequest('POST', '/api/players/register', {
        name,
        language: 'en',
        deviceId: `ws-test-device-${Date.now()}-${Math.random()}`
      });
      
      if (result.success && result.data.success && result.data.player) {
        this.testPlayers.push(result.data.player);
        this.log(true, `Created test player: ${name}`, `ID: ${result.data.player.id}`);
      } else {
        this.log(false, `Failed to create player: ${name}`, `Error: ${result.data?.error || 'Unknown'}`);
      }
    }
    
    if (this.testPlayers.length < 2) {
      throw new Error('Need at least 2 players for WebSocket testing');
    }
  }

  async testBasicWebSocketConnection() {
    console.log('\n🔌 Testing Basic WebSocket Connection');
    
    try {
      const connection = await this.createWebSocketConnection('BasicTest');
      this.sockets.push(connection);
      
      // Wait for welcome message
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      const welcomeEvent = connection.events.find(e => e.type === 'welcome');
      if (welcomeEvent) {
        this.log(true, 'Welcome message received', `Message: ${welcomeEvent.data.message}`);
      } else {
        this.log(false, 'Welcome message missing', 'No welcome event received');
      }
      
    } catch (error) {
      this.log(false, 'Basic WebSocket connection failed', error.message);
    }
  }

  async testPlayerConnectionEvents() {
    console.log('\n👤 Testing Player Connection Events');
    
    if (this.testPlayers.length < 2) {
      this.log(false, 'Player connection tests skipped', 'Not enough test players');
      return;
    }
    
    try {
      // Create connections for two players
      const player1Connection = await this.createWebSocketConnection('Player1');
      const player2Connection = await this.createWebSocketConnection('Player2');
      
      this.sockets.push(player1Connection, player2Connection);
      
      // Wait for initial connection setup
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Player 1 connects
      player1Connection.ws.send(JSON.stringify({
        type: 'player-connect',
        playerId: this.testPlayers[0].id
      }));
      
      // Wait for response
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Player 2 connects
      player2Connection.ws.send(JSON.stringify({
        type: 'player-connect', 
        playerId: this.testPlayers[1].id
      }));
      
      // Wait for all events to propagate
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      // Check if both players received player list updates
      const player1ListUpdate = player1Connection.events.find(e => e.type === 'player-list-updated');
      const player2ListUpdate = player2Connection.events.find(e => e.type === 'player-list-updated');
      
      if (player1ListUpdate && player2ListUpdate) {
        this.log(true, 'Player list updates received', `Both players notified of connections`);
      } else {
        this.log(false, 'Player list updates missing', `P1: ${!!player1ListUpdate}, P2: ${!!player2ListUpdate}`);
      }
      
    } catch (error) {
      this.log(false, 'Player connection events failed', error.message);
    }
  }

  async testRealTimePhraseDelivery() {
    console.log('\n📨 Testing Real-time Phrase Delivery');
    
    if (this.testPlayers.length < 2 || this.sockets.length < 2) {
      this.log(false, 'Phrase delivery tests skipped', 'Not enough connected players');
      return;
    }
    
    try {
      // Create a phrase from player 1 to player 2
      const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
        content: 'websocket test',
        language: 'en',
        senderId: this.testPlayers[0].id,
        targetId: this.testPlayers[1].id,
        hint: 'real-time delivery test'
      });
      
      if (!phraseResult.success) {
        this.log(false, 'Phrase creation failed', `Error: ${phraseResult.data?.error || 'Unknown'}`);
        return;
      }
      
      this.log(true, 'Phrase created for delivery test', `ID: ${phraseResult.data.phrase.id}`);
      
      // Wait for WebSocket events to propagate
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      // Check if any socket received a new-phrase event
      let phraseEventReceived = false;
      for (const socket of this.sockets) {
        const phraseEvent = socket.events.find(e => e.type === 'new-phrase');
        if (phraseEvent) {
          phraseEventReceived = true;
          this.log(true, `${socket.name} received phrase notification`, `Content: ${phraseEvent.data.phrase?.content || 'No content'}`);
          break;
        }
      }
      
      if (!phraseEventReceived) {
        this.log(false, 'Phrase delivery notification missing', 'No socket received new-phrase event');
      }
      
    } catch (error) {
      this.log(false, 'Real-time phrase delivery failed', error.message);
    }
  }

  async testMultiplayerScenario() {
    console.log('\n🎮 Testing Complete Multiplayer Scenario');
    
    if (this.testPlayers.length < 2) {
      this.log(false, 'Multiplayer scenario skipped', 'Not enough players');
      return;
    }
    
    try {
      // Simulate a complete game flow
      // 1. Two players connect
      // 2. Player 1 sends phrase to Player 2
      // 3. Player 2 receives and completes the phrase
      // 4. Both players get completion notification
      
      // Create phrase
      const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
        content: 'game flow test',
        language: 'en',
        senderId: this.testPlayers[0].id,
        targetId: this.testPlayers[1].id,
        hint: 'multiplayer test'
      });
      
      if (phraseResult.success) {
        const phraseId = phraseResult.data.phrase.id;
        this.log(true, 'Multiplayer phrase created', `ID: ${phraseId}`);
        
        // Wait for delivery
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Complete the phrase
        const completionResult = await this.makeRequest('POST', `/api/phrases/${phraseId}/complete`, {
          playerId: this.testPlayers[1].id,
          hintsUsed: 0,
          completionTime: 5000,
          celebrationEmojis: ['🎉', '🎮']
        });
        
        if (completionResult.success) {
          this.log(true, 'Phrase completed', `Score: ${completionResult.data.completion?.scoreAwarded || 'unknown'}`);
          
          // Wait for completion events
          await new Promise(resolve => setTimeout(resolve, 2000));
          
          // Check for completion notifications
          let completionNotified = false;
          for (const socket of this.sockets) {
            const completionEvent = socket.events.find(e => e.type === 'phrase-completed' || e.type === 'player-scored');
            if (completionEvent) {
              completionNotified = true;
              this.log(true, `${socket.name} notified of completion`, `Event: ${completionEvent.type}`);
              break;
            }
          }
          
          if (!completionNotified) {
            this.log(false, 'Completion notification missing', 'No sockets received completion events');
          }
          
        } else {
          this.log(false, 'Phrase completion failed', `Error: ${completionResult.data?.error || 'Unknown'}`);
        }
      }
      
    } catch (error) {
      this.log(false, 'Multiplayer scenario failed', error.message);
    }
  }

  async testWebSocketStability() {
    console.log('\n🔧 Testing WebSocket Connection Stability');
    
    try {
      // Create a connection and monitor it for stability
      const connection = await this.createWebSocketConnection('StabilityTest');
      this.sockets.push(connection);
      
      const initialEventCount = connection.events.length;
      
      // Send periodic ping messages
      for (let i = 0; i < 5; i++) {
        connection.ws.ping();
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      
      if (connection.connected) {
        this.log(true, 'WebSocket connection stable', 'Survived 5 ping tests');
      } else {
        this.log(false, 'WebSocket connection unstable', 'Connection lost during ping tests');
      }
      
    } catch (error) {
      this.log(false, 'WebSocket stability test failed', error.message);
    }
  }

  async testMonitoringNamespace() {
    console.log('\n📊 Testing Monitoring Namespace (Optional)');
    
    try {
      // Attempt to connect to monitoring namespace
      const monitoringWS = new WebSocket(`${WS_URL}/monitoring`);
      
      let connected = false;
      let authRequired = false;
      
      const testPromise = new Promise((resolve) => {
        monitoringWS.on('open', () => {
          connected = true;
          this.log(true, 'Monitoring namespace accessible', 'Connected without auth (dev mode?)');
          resolve();
        });
        
        monitoringWS.on('error', (error) => {
          if (error.message.includes('Authentication') || error.message.includes('401')) {
            authRequired = true;
            this.log(true, 'Monitoring namespace protected', 'Authentication required (secure)');
          } else {
            this.log(false, 'Monitoring namespace error', error.message);
          }
          resolve();
        });
        
        setTimeout(resolve, 3000); // Timeout after 3 seconds
      });
      
      await testPromise;
      
      if (connected) {
        monitoringWS.close();
      }
      
    } catch (error) {
      this.log(false, 'Monitoring namespace test failed', error.message);
    }
  }

  async cleanup() {
    console.log('\n🧹 Cleaning up connections');
    
    for (const socket of this.sockets) {
      if (socket.ws && socket.connected) {
        socket.ws.close();
      }
    }
    
    // Wait for connections to close
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  async runAllTests() {
    console.log('🚀 Starting WebSocket Real-time Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.setupTestPlayers();
      await this.testBasicWebSocketConnection();
      await this.testPlayerConnectionEvents();
      await this.testRealTimePhraseDelivery();
      await this.testMultiplayerScenario();
      await this.testWebSocketStability();
      await this.testMonitoringNamespace();
      
    } catch (error) {
      this.log(false, 'Test suite error', error.message);
    } finally {
      await this.cleanup();
    }

    console.log('\n📊 WEBSOCKET REAL-TIME TEST SUMMARY');
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
  const tester = new WebSocketRealTimeTest();
  tester.runAllTests().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = WebSocketRealTimeTest;