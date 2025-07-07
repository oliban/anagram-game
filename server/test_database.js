const { testConnection, getStats } = require('./database/connection');
const DatabasePlayer = require('./models/DatabasePlayer');
const DatabasePhrase = require('./models/DatabasePhrase');

async function testDatabase() {
  console.log('🧪 Testing database connection and models...\n');
  
  try {
    // Test connection
    console.log('1. Testing database connection...');
    const connected = await testConnection();
    if (!connected) {
      throw new Error('Database connection failed');
    }
    console.log('✅ Database connection successful\n');

    // Test player creation
    console.log('2. Testing player creation...');
    const testPlayer = await DatabasePlayer.createPlayer('TestPlayer', 'test-socket-123');
    console.log(`✅ Player created: ${testPlayer.name} (${testPlayer.id})\n`);

    // Test phrase creation
    console.log('3. Testing phrase creation...');
    const testPhrase = await DatabasePhrase.createPhrase(
      'cat dog run', 
      'Three animals and an action',
      { 
        difficultyLevel: 2, 
        isGlobal: true, 
        createdByPlayerId: testPlayer.id 
      }
    );
    console.log(`✅ Phrase created: "${testPhrase.content}" with hint: "${testPhrase.hint}"\n`);

    // Test getting next phrase
    console.log('4. Testing phrase retrieval...');
    const nextPhrase = await DatabasePhrase.getNextPhraseForPlayer(testPlayer.id);
    if (nextPhrase) {
      console.log(`✅ Next phrase for player: "${nextPhrase.content}" (${nextPhrase.phraseType})\n`);
    } else {
      console.log(`📭 No phrases available for player ${testPlayer.id}\n`);
    }

    // Test phrase completion
    if (nextPhrase) {
      console.log('5. Testing phrase completion...');
      const completed = await DatabasePhrase.completePhrase(testPlayer.id, nextPhrase.id, 100, 5000);
      console.log(`✅ Phrase completion: ${completed ? 'Success' : 'Failed'}\n`);
    }

    // Test online players
    console.log('6. Testing online players...');
    const onlinePlayers = await DatabasePlayer.getOnlinePlayers();
    console.log(`✅ Online players: ${onlinePlayers.length}\n`);

    // Test phrase stats
    console.log('7. Testing phrase statistics...');
    const phraseStats = await DatabasePhrase.getStats();
    console.log(`✅ Phrase stats:`, phraseStats, '\n');

    // Test database stats
    console.log('8. Testing database statistics...');
    const dbStats = await getStats();
    console.log(`✅ Database stats:`, dbStats, '\n');

    console.log('🎉 All database tests passed successfully!');

  } catch (error) {
    console.error('❌ Database test failed:', error.message);
    console.error(error.stack);
  }
}

// Run tests if this file is executed directly
if (require.main === module) {
  testDatabase().then(() => {
    process.exit(0);
  }).catch((error) => {
    console.error('Test runner error:', error);
    process.exit(1);
  });
}

module.exports = { testDatabase };