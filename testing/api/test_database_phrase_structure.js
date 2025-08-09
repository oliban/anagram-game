#!/usr/bin/env node

/**
 * DatabasePhrase Structure Validation Test
 * Tests the enhanced getPublicInfo() method and data structure
 */

const BASE_URL = 'http://localhost:3000';

class DatabasePhraseStructureTest {
  constructor() {
    this.testResults = [];
    this.testPlayer = null;
    this.testPhrase = null;
  }

  async runTest(name, testFunction) {
    try {
      console.log(`\n🧪 Testing: ${name}`);
      const startTime = Date.now();
      await testFunction();
      const duration = Date.now() - startTime;
      console.log(`✅ ${name} - PASSED (${duration}ms)`);
      this.testResults.push({ name, status: 'PASSED', duration });
    } catch (error) {
      console.log(`❌ ${name} - FAILED: ${error.message}`);
      this.testResults.push({ name, status: 'FAILED', error: error.message });
    }
  }

  async setupTestData() {
    console.log('📋 Setting up test data...');
    
    // Create test player
    const playerResponse = await fetch(`${BASE_URL}/api/players/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'PhraseStructureTestPlayer' })
    });
    
    if (!playerResponse.ok) {
      throw new Error('Failed to create test player');
    }
    
    this.testPlayer = await playerResponse.json();
    console.log(`👤 Created test player: ${this.testPlayer.player.id}`);
    
    // Create test phrase
    const phraseResponse = await fetch(`${BASE_URL}/api/phrases/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: 'hello world example',
        hint: 'A simple greeting to everyone on the planet',
        senderId: this.testPlayer.player.id,
        isGlobal: true
      })
    });
    
    if (!phraseResponse.ok) {
      throw new Error('Failed to create test phrase');
    }
    
    this.testPhrase = await phraseResponse.json();
    console.log(`📝 Created test phrase: ${this.testPhrase.phrase.id}`);
  }

  async testPhraseCreationResponseStructure() {
    // Test the structure returned by phrase creation endpoint
    const phrase = this.testPhrase.phrase;
    
    // Validate required fields are present
    const requiredFields = [
      'id', 'content', 'hint', 'difficultyLevel', 'isGlobal', 
      'createdAt', 'senderId'
    ];
    
    for (const field of requiredFields) {
      if (!(field in phrase)) {
        throw new Error(`Missing required field '${field}' in phrase creation response`);
      }
    }
    
    // Validate enhanced fields specifically
    if (!phrase.createdAt) {
      throw new Error('Missing createdAt field in phrase response (recent enhancement)');
    }
    
    // Validate createdAt is a valid date
    const createdAt = new Date(phrase.createdAt);
    if (isNaN(createdAt.getTime())) {
      throw new Error('Invalid createdAt date format');
    }
    
    // Validate the createdAt is recent (within last 5 minutes)
    const now = new Date();
    const timeDiff = Math.abs(now - createdAt);
    if (timeDiff > 5 * 60 * 1000) { // 5 minutes in milliseconds
      throw new Error('CreatedAt timestamp is not recent enough');
    }
    
    console.log(`📊 Phrase creation response structure validated:`);
    console.log(`   - id: ${phrase.id}`);
    console.log(`   - content: "${phrase.content}"`);
    console.log(`   - hint: "${phrase.hint}"`);
    console.log(`   - difficultyLevel: ${phrase.difficultyLevel}`);
    console.log(`   - isGlobal: ${phrase.isGlobal}`);
    console.log(`   - createdAt: ${phrase.createdAt}`);
    console.log(`   - senderId: ${phrase.senderId}`);
    console.log(`   - isConsumed: ${phrase.isConsumed}`);
  }

  async testPhraseRetrievalStructure() {
    // Test the structure returned by phrase retrieval endpoint
    const response = await fetch(`${BASE_URL}/api/phrases/for/${this.testPlayer.player.id}`);
    
    if (!response.ok) {
      throw new Error('Failed to retrieve phrases');
    }
    
    const data = await response.json();
    
    if (!data.phrases || !Array.isArray(data.phrases)) {
      throw new Error('Invalid phrases array in retrieval response');
    }
    
    if (data.phrases.length === 0) {
      console.log('⚠️ No phrases found for retrieval structure test (this is okay)');
      return;
    }
    
    // Test the first phrase structure
    const phrase = data.phrases[0];
    
    // Validate required fields
    const requiredFields = ['id', 'content', 'createdAt'];
    
    for (const field of requiredFields) {
      if (!(field in phrase)) {
        throw new Error(`Missing required field '${field}' in phrase retrieval response`);
      }
    }
    
    // Validate createdAt field specifically
    if (!phrase.createdAt) {
      throw new Error('Missing createdAt field in phrase retrieval (recent enhancement)');
    }
    
    const createdAt = new Date(phrase.createdAt);
    if (isNaN(createdAt.getTime())) {
      throw new Error('Invalid createdAt date format in retrieval');
    }
    
    console.log(`📊 Phrase retrieval structure validated:`);
    console.log(`   - id: ${phrase.id}`);
    console.log(`   - content: "${phrase.content}"`);
    console.log(`   - createdAt: ${phrase.createdAt}`);
    console.log(`   - senderName: ${phrase.senderName || 'N/A'}`);
  }

  async testPhrasePreviewStructure() {
    // Test the structure returned by phrase preview endpoint (hint system)
    const response = await fetch(
      `${BASE_URL}/api/phrases/${this.testPhrase.phrase.id}/preview?playerId=${this.testPlayer.player.id}`
    );
    
    if (!response.ok) {
      throw new Error('Failed to get phrase preview');
    }
    
    const data = await response.json();
    
    if (!data.success || !data.phrase) {
      throw new Error('Invalid phrase preview response structure');
    }
    
    const phrase = data.phrase;
    
    // Validate preview structure includes enhanced fields
    const requiredFields = ['id', 'content', 'hint', 'difficultyLevel', 'isGlobal'];
    
    for (const field of requiredFields) {
      if (!(field in phrase)) {
        throw new Error(`Missing required field '${field}' in phrase preview`);
      }
    }
    
    // Validate hint status and score preview are included
    if (!phrase.hintStatus) {
      throw new Error('Missing hintStatus in phrase preview');
    }
    
    if (!phrase.scorePreview) {
      throw new Error('Missing scorePreview in phrase preview');
    }
    
    console.log(`📊 Phrase preview structure validated:`);
    console.log(`   - id: ${phrase.id}`);
    console.log(`   - content: "${phrase.content}"`);
    console.log(`   - hint: "${phrase.hint}"`);
    console.log(`   - difficultyLevel: ${phrase.difficultyLevel}`);
    console.log(`   - hintStatus: ${JSON.stringify(phrase.hintStatus)}`);
    console.log(`   - scorePreview: ${JSON.stringify(phrase.scorePreview)}`);
  }

  async testGlobalPhraseStructure() {
    // Test the structure returned by global phrases endpoint
    const response = await fetch(`${BASE_URL}/api/phrases/global`);
    
    if (!response.ok) {
      throw new Error('Failed to retrieve global phrases');
    }
    
    const data = await response.json();
    
    if (!data.phrases || !Array.isArray(data.phrases)) {
      throw new Error('Invalid global phrases array structure');
    }
    
    if (data.phrases.length === 0) {
      console.log('⚠️ No global phrases found for structure test');
      return;
    }
    
    // Test the first global phrase structure
    const phrase = data.phrases[0];
    
    // Validate required fields for global phrases
    const requiredFields = ['id', 'content', 'hint', 'difficultyLevel', 'createdAt'];
    
    for (const field of requiredFields) {
      if (!(field in phrase)) {
        throw new Error(`Missing required field '${field}' in global phrase`);
      }
    }
    
    // Validate createdAt field specifically for global phrases
    const createdAt = new Date(phrase.createdAt);
    if (isNaN(createdAt.getTime())) {
      throw new Error('Invalid createdAt date format in global phrases');
    }
    
    console.log(`📊 Global phrase structure validated:`);
    console.log(`   - id: ${phrase.id}`);
    console.log(`   - content: "${phrase.content}"`);
    console.log(`   - hint: "${phrase.hint}"`);
    console.log(`   - difficultyLevel: ${phrase.difficultyLevel}`);
    console.log(`   - createdAt: ${phrase.createdAt}`);
  }

  printSummary() {
    console.log('\n' + '='.repeat(60));
    console.log('📊 DATABASE PHRASE STRUCTURE TEST SUMMARY');
    console.log('='.repeat(60));
    
    const passed = this.testResults.filter(r => r.status === 'PASSED').length;
    const failed = this.testResults.filter(r => r.status === 'FAILED').length;
    const total = this.testResults.length;
    
    console.log(`Total tests: ${total}`);
    console.log(`✅ Passed: ${passed}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`📈 Success rate: ${((passed / total) * 100).toFixed(1)}%`);
    
    if (failed > 0) {
      console.log('\n❌ Failed tests:');
      this.testResults
        .filter(r => r.status === 'FAILED')
        .forEach(test => console.log(`  - ${test.name}: ${test.error}`));
    }
    
    console.log('\n🎯 DatabasePhrase Structure Features Tested:');
    console.log('  ✅ Enhanced getPublicInfo() with createdAt field');
    console.log('  ✅ Phrase creation response structure');
    console.log('  ✅ Phrase retrieval response structure');
    console.log('  ✅ Phrase preview response structure (hint system)');
    console.log('  ✅ Global phrases response structure');
    console.log('  ✅ Date format validation and recentness checks');
    
    console.log('\n🔗 API Endpoints Tested:');
    console.log('  - POST /api/phrases/create');
    console.log('  - GET  /api/phrases/for/:playerId');
    console.log('  - GET  /api/phrases/:phraseId/preview');
    console.log('  - GET  /api/phrases/global');
    
    console.log('='.repeat(60));
  }

  async run() {
    console.log('🚀 Starting DatabasePhrase Structure Test Suite');
    console.log('🎯 Testing enhanced getPublicInfo() method and data structures');
    
    try {
      await this.setupTestData();
      
      await this.runTest('Phrase Creation Response Structure', () => this.testPhraseCreationResponseStructure());
      await this.runTest('Phrase Retrieval Structure', () => this.testPhraseRetrievalStructure());
      await this.runTest('Phrase Preview Structure', () => this.testPhrasePreviewStructure());
      await this.runTest('Global Phrase Structure', () => this.testGlobalPhraseStructure());
      
    } catch (error) {
      console.error('❌ Setup failed:', error.message);
    }
    
    this.printSummary();
  }
}

// Run the test suite
if (require.main === module) {
  const tester = new DatabasePhraseStructureTest();
  tester.run().catch(console.error);
}

module.exports = DatabasePhraseStructureTest;