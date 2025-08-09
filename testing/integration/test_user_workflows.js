#!/usr/bin/env node

/**
 * Integration Testing for Complete User Workflows
 * Tests end-to-end user scenarios that span multiple API endpoints
 */

const http = require('http');
let io;
try {
  io = require('socket.io-client');
} catch (e) {
  console.log('⚠️  socket.io-client not available for real-time workflow testing');
}

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🔄 User Workflow Integration Tests`);
console.log(`📡 Server: ${API_URL}`);

class UserWorkflowTest {
  constructor() {
    this.passed = 0;
    this.failed = 0;
    this.users = [];
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

  async createSocket(name) {
    if (!io) return null;
    
    return new Promise((resolve, reject) => {
      const socket = io(API_URL, {
        transports: ['websocket', 'polling'],
        timeout: 5000
      });

      socket.on('connect', () => {
        this.sockets.push({ name, socket });
        resolve(socket);
      });

      socket.on('connect_error', (error) => {
        reject(error);
      });

      setTimeout(() => reject(new Error('Socket connection timeout')), 10000);
    });
  }

  async testNewUserOnboarding() {
    console.log('\n👋 Testing: New User Onboarding Workflow');
    
    // Step 1: User attempts to access phrases before registration
    const unregisteredResult = await this.makeRequest('GET', '/api/phrases/for/invalid-user');
    
    if (unregisteredResult.status === 404) {
      this.log(true, 'Unregistered user protection', 'Correctly blocks access to phrases');
    } else {
      this.log(false, 'Unregistered user protection', `Unexpected status: ${unregisteredResult.status}`);
    }
    
    // Step 2: User registers
    const timestamp = Date.now();
    const newUser = await this.makeRequest('POST', '/api/players/register', {
      name: `NewUser${timestamp}`,
      language: 'en',
      deviceId: `onboarding-device-${timestamp}`
    });
    
    if (newUser.success && newUser.data.player) {
      this.log(true, 'User registration successful', `User: ${newUser.data.player.name}, ID: ${newUser.data.player.id}`);
      this.users.push(newUser.data.player);
    } else {
      this.log(false, 'User registration failed', `Error: ${newUser.data?.error || 'Unknown'}`);
      return;
    }
    
    // Step 3: User can now access their phrase queue
    const userId = newUser.data.player.id;
    const phrasesResult = await this.makeRequest('GET', `/api/phrases/for/${userId}`);
    
    if (phrasesResult.success) {
      const phraseCount = phrasesResult.data.phrases?.length || 0;
      this.log(true, 'First-time phrase access', `Found ${phraseCount} phrases for new user`);
    } else {
      this.log(false, 'First-time phrase access', `Status: ${phrasesResult.status}`);
    }
    
    // Step 4: User views global stats and leaderboards
    const statsResult = await this.makeRequest('GET', '/api/stats');
    if (statsResult.success) {
      this.log(true, 'Global stats access', 'New user can view game statistics');
    } else {
      this.log(false, 'Global stats access', `Status: ${statsResult.status}`);
    }
    
    const leaderboardResult = await this.makeRequest('GET', '/api/leaderboard/total');
    if (leaderboardResult.success) {
      this.log(true, 'Leaderboard access', 'New user can view leaderboards');
    } else {
      this.log(false, 'Leaderboard access', `Status: ${leaderboardResult.status}`);
    }
  }

  async testSocialMultiplayerWorkflow() {
    console.log('\n👥 Testing: Social Multiplayer Workflow');
    
    // Create two friends who want to play together
    const timestamp = Date.now();
    
    const friend1Result = await this.makeRequest('POST', '/api/players/register', {
      name: `Friend1_${timestamp}`,
      language: 'en',
      deviceId: `friend1-device-${timestamp}`
    });
    
    const friend2Result = await this.makeRequest('POST', '/api/players/register', {
      name: `Friend2_${timestamp}`,
      language: 'en',
      deviceId: `friend2-device-${timestamp}`
    });
    
    if (!friend1Result.success || !friend2Result.success) {
      this.log(false, 'Friend registration', 'Could not create test friends');
      return;
    }
    
    const friend1 = friend1Result.data.player;
    const friend2 = friend2Result.data.player;
    this.users.push(friend1, friend2);
    
    this.log(true, 'Friends registered', `${friend1.name} and ${friend2.name}`);
    
    // Step 1: Friend1 connects via WebSocket (if available)
    let friend1Socket = null;
    if (io) {
      try {
        friend1Socket = await this.createSocket('Friend1');
        friend1Socket.emit('player-connect', { playerId: friend1.id });
        this.log(true, 'Friend1 connected via WebSocket', `Socket ID: ${friend1Socket.id}`);
      } catch (error) {
        this.log(false, 'Friend1 WebSocket connection', error.message);
      }
    }
    
    // Step 2: Friend1 creates a custom phrase for Friend2
    const phraseContent = `hello friend`;
    const phraseResult = await this.makeRequest('POST', '/api/phrases/create', {
      content: phraseContent,
      language: 'en',
      senderId: friend1.id,
      targetId: friend2.id,
      hint: 'from your buddy'
    });
    
    if (phraseResult.success) {
      this.log(true, 'Friend phrase created', `"${phraseContent}" sent from ${friend1.name} to ${friend2.name}`);
    } else {
      this.log(false, 'Friend phrase creation', `Error: ${phraseResult.data?.error || 'Unknown'}`);
      return;
    }
    
    const phraseId = phraseResult.data.phrase.id;
    
    // Step 3: Friend2 connects and sees the new phrase
    let friend2Socket = null;
    if (io) {
      try {
        friend2Socket = await this.createSocket('Friend2');
        friend2Socket.emit('player-connect', { playerId: friend2.id });
        this.log(true, 'Friend2 connected via WebSocket', `Socket ID: ${friend2Socket.id}`);
        
        // Wait for potential real-time notification
        await new Promise(resolve => setTimeout(resolve, 1000));
      } catch (error) {
        this.log(false, 'Friend2 WebSocket connection', error.message);
      }
    }
    
    // Step 4: Friend2 retrieves their phrases (should include the one from Friend1)
    const friend2PhrasesResult = await this.makeRequest('GET', `/api/phrases/for/${friend2.id}`);
    
    if (friend2PhrasesResult.success) {
      const phrases = friend2PhrasesResult.data.phrases || [];
      const friendPhrase = phrases.find(p => p.id === phraseId);
      
      if (friendPhrase) {
        this.log(true, 'Friend phrase received', `Friend2 found phrase from Friend1: "${friendPhrase.content}"`);
      } else {
        this.log(false, 'Friend phrase delivery', 'Phrase not found in Friend2\'s queue');
        return;
      }
    } else {
      this.log(false, 'Friend2 phrase retrieval', `Status: ${friend2PhrasesResult.status}`);
      return;
    }
    
    // Step 5: Friend2 completes the phrase
    const completionResult = await this.makeRequest('POST', `/api/phrases/${phraseId}/complete`, {
      playerId: friend2.id,
      hintsUsed: 0,
      completionTime: 5000,
      celebrationEmojis: [
        { id: 1, emoji_character: '🎉', rarity_tier: 'Common', drop_rate_percentage: 15.0, points_reward: 10 }
      ]
    });
    
    if (completionResult.success) {
      const score = completionResult.data.completion?.finalScore || 0;
      this.log(true, 'Friend phrase completed', `Friend2 completed phrase with score: ${score}`);
    } else {
      this.log(false, 'Friend phrase completion', `Error: ${completionResult.data?.error || 'Unknown'}`);
    }
    
    // Step 6: Both friends check updated leaderboards
    const leaderboardResult = await this.makeRequest('GET', '/api/leaderboard/total');
    if (leaderboardResult.success) {
      const players = leaderboardResult.data.players || [];
      const friend1Rank = players.findIndex(p => p.id === friend1.id) + 1;
      const friend2Rank = players.findIndex(p => p.id === friend2.id) + 1;
      
      this.log(true, 'Multiplayer leaderboard update', `Friend1: rank ${friend1Rank || 'unranked'}, Friend2: rank ${friend2Rank || 'unranked'}`);
    }
    
    // Cleanup sockets
    if (friend1Socket) friend1Socket.disconnect();
    if (friend2Socket) friend2Socket.disconnect();
  }

  async testSkillProgressionWorkflow() {
    console.log('\n📈 Testing: Skill Progression Workflow');
    
    // Create a new player to track progression
    const timestamp = Date.now();
    const learnerResult = await this.makeRequest('POST', '/api/players/register', {
      name: `Learner${timestamp}`,
      language: 'en',
      deviceId: `learner-device-${timestamp}`
    });
    
    if (!learnerResult.success) {
      this.log(false, 'Learner registration', 'Could not create learner');
      return;
    }
    
    const learner = learnerResult.data.player;
    this.users.push(learner);
    this.log(true, 'Learner registered', `${learner.name}`);
    
    // Step 1: Check initial skill configuration
    const skillLevelsResult = await this.makeRequest('GET', '/api/config/levels');
    if (skillLevelsResult.success) {
      const levels = skillLevelsResult.data.config?.skillLevels || [];
      this.log(true, 'Skill levels loaded', `${levels.length} skill levels available`);
    } else {
      this.log(false, 'Skill levels loading', `Status: ${skillLevelsResult.status}`);
    }
    
    // Step 2: Get difficulty-appropriate phrases
    const phrasesResult = await this.makeRequest('GET', `/api/phrases/for/${learner.id}?level=1`);
    
    if (phrasesResult.success) {
      const phrases = phrasesResult.data.phrases || [];
      this.log(true, 'Beginner phrases retrieved', `${phrases.length} level-appropriate phrases`);
      
      // Step 3: Complete several phrases to simulate progression
      let completedCount = 0;
      const maxPhrases = Math.min(3, phrases.length);
      
      for (let i = 0; i < maxPhrases; i++) {
        const phrase = phrases[i];
        
        const completionResult = await this.makeRequest('POST', `/api/phrases/${phrase.id}/complete`, {
          playerId: learner.id,
          hintsUsed: i % 2, // Use hints on every other phrase
          completionTime: 3000 + (i * 1000),
          celebrationEmojis: [
            { id: 1, emoji_character: '📚', rarity_tier: 'Common', drop_rate_percentage: 20.0, points_reward: 5 }
          ]
        });
        
        if (completionResult.success) {
          completedCount++;
          const score = completionResult.data.completion?.finalScore || 0;
          this.log(true, `Progression phrase ${i + 1}`, `Completed "${phrase.content}" - Score: ${score}`);
        } else {
          this.log(false, `Progression phrase ${i + 1}`, `Failed to complete: ${completionResult.data?.error || 'Unknown'}`);
        }
        
        // Brief pause between completions
        await new Promise(resolve => setTimeout(resolve, 500));
      }
      
      this.log(true, 'Skill progression simulation', `Completed ${completedCount}/${maxPhrases} phrases`);
      
    } else {
      this.log(false, 'Beginner phrases', `Status: ${phrasesResult.status}`);
    }
    
    // Step 4: Test difficulty analysis for learning
    const difficultyTest = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
      phrase: 'simple test',
      language: 'en'
    });
    
    if (difficultyTest.success) {
      const score = difficultyTest.data.score;
      const difficulty = difficultyTest.data.difficulty;
      this.log(true, 'Difficulty analysis for learning', `"simple test" = ${score} (${difficulty})`);
    } else {
      this.log(false, 'Difficulty analysis', `Status: ${difficultyTest.status}`);
    }
  }

  async testContributionWorkflow() {
    console.log('\n💡 Testing: Community Contribution Workflow');
    
    // Step 1: Test phrase creation with analysis
    const contributionPhrases = [
      'quick test phrase',  
      'short test words',  // Fixed: 3 words, each ≤7 chars
      'good game'  // Fixed: 2 words, each ≤7 chars
    ];
    
    for (const phraseContent of contributionPhrases) {
      // First, analyze the difficulty
      const analysisResult = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
        phrase: phraseContent,
        language: 'en'
      });
      
      if (analysisResult.success) {
        const score = analysisResult.data.score;
        const difficulty = analysisResult.data.difficulty;
        this.log(true, 'Community phrase analysis', `"${phraseContent}" = ${score} (${difficulty})`);
        
        // Step 2: Create as global contribution if user exists
        if (this.users.length > 0) {
          const contributor = this.users[0];
          const creationResult = await this.makeRequest('POST', '/api/phrases/create', {
            content: phraseContent,
            language: 'en',
            senderId: contributor.id,
            isGlobal: true,
            hint: 'community contribution'
          });
          
          if (creationResult.success) {
            this.log(true, 'Global phrase contribution', `"${phraseContent}" added by ${contributor.name}`);
          } else {
            this.log(false, 'Global phrase contribution', `Error: ${creationResult.data?.error || 'Unknown'}`);
          }
        }
        
      } else {
        this.log(false, 'Contribution analysis', `"${phraseContent}" - Status: ${analysisResult.status}`);
      }
    }
    
    // Step 3: Test contribution system endpoints
    const contributionTokenResult = await this.makeRequest('POST', '/api/contribution/test-token/submit', {
      content: 'test contribution',
      language: 'en'
    });
    
    // This should fail with invalid token (expected behavior)
    if (contributionTokenResult.status >= 400) {
      this.log(true, 'Contribution token validation', 'Correctly rejects invalid tokens');
    } else {
      this.log(false, 'Contribution token validation', `Unexpected success: ${contributionTokenResult.status}`);
    }
  }

  async testErrorRecoveryWorkflows() {
    console.log('\n🔧 Testing: Error Recovery Workflows');
    
    // Test 1: Invalid player ID handling
    const invalidPlayerResult = await this.makeRequest('GET', '/api/phrases/for/not-a-valid-uuid');
    if (invalidPlayerResult.status === 404) {
      this.log(true, 'Invalid player ID handling', 'Returns 404 for malformed UUIDs');
    } else {
      this.log(false, 'Invalid player ID handling', `Status: ${invalidPlayerResult.status}`);
    }
    
    // Test 2: Duplicate player registration
    if (this.users.length > 0) {
      const existingUser = this.users[0];
      const duplicateResult = await this.makeRequest('POST', '/api/players/register', {
        name: existingUser.name,
        language: 'en',
        deviceId: existingUser.deviceId || 'test-device'
      });
      
      // Should fail due to duplicate name
      if (!duplicateResult.success) {
        this.log(true, 'Duplicate player prevention', 'Correctly prevents duplicate registrations');
      } else {
        this.log(false, 'Duplicate player prevention', 'Should have blocked duplicate registration');
      }
    }
    
    // Test 3: Invalid phrase completion
    const invalidCompletionResult = await this.makeRequest('POST', '/api/phrases/non-existent-phrase/complete', {
      playerId: this.users[0]?.id || 'test-id',
      hintsUsed: 0,
      completionTime: 1000
    });
    
    if (invalidCompletionResult.status === 404) {
      this.log(true, 'Invalid phrase completion', 'Returns 404 for non-existent phrases');
    } else {
      this.log(false, 'Invalid phrase completion', `Status: ${invalidCompletionResult.status}`);
    }
    
    // Test 4: Malformed request handling
    const malformedResult = await this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
      // Missing required 'phrase' field
      language: 'en'
    });
    
    if (malformedResult.status === 400) {
      this.log(true, 'Malformed request handling', 'Returns 400 for missing required fields');
    } else {
      this.log(false, 'Malformed request handling', `Status: ${malformedResult.status}`);
    }
  }

  async cleanup() {
    console.log('\n🧹 Cleaning up test resources');
    
    // Disconnect all sockets
    for (const socket of this.sockets) {
      if (socket.socket && socket.socket.connected) {
        socket.socket.disconnect();
      }
    }
    
    this.log(true, 'Cleanup completed', `Disconnected ${this.sockets.length} sockets`);
  }

  async runAllWorkflows() {
    console.log('🚀 Starting User Workflow Integration Tests');
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.testNewUserOnboarding();
      await this.testSocialMultiplayerWorkflow();
      await this.testSkillProgressionWorkflow();
      await this.testContributionWorkflow();
      await this.testErrorRecoveryWorkflows();
    } catch (error) {
      this.log(false, 'Workflow test error', error.message);
    } finally {
      await this.cleanup();
    }

    console.log('\n📊 USER WORKFLOW TEST SUMMARY');
    console.log('='.repeat(60));
    console.log(`✅ Passed: ${this.passed}`);
    console.log(`❌ Failed: ${this.failed}`);
    console.log(`📊 Total: ${this.passed + this.failed}`);
    
    const successRate = this.failed === 0 ? 100 : ((this.passed / (this.passed + this.failed)) * 100).toFixed(1);
    console.log(`📈 Success Rate: ${successRate}%`);
    
    console.log('\n🎯 Workflow Coverage:');
    console.log('  ✅ New user onboarding');
    console.log('  ✅ Social multiplayer interactions');
    console.log('  ✅ Skill progression and difficulty scaling');
    console.log('  ✅ Community contribution system');
    console.log('  ✅ Error recovery and edge cases');

    console.log(`\n🎯 Integration test completed at ${new Date().toISOString()}`);
    
    return this.failed === 0;
  }
}

// Run tests
if (require.main === module) {
  const tester = new UserWorkflowTest();
  tester.runAllWorkflows().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('💥 Workflow test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = UserWorkflowTest;