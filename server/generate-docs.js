const swaggerAutogen = require('swagger-autogen')();

const doc = {
  info: {
    title: 'Anagram Game Multiplayer Server API',
    version: '1.0.0',
    description: 'A comprehensive API for the Anagram Game multiplayer server with PostgreSQL database, real-time WebSocket communication, and advanced phrase management.',
    contact: {
      name: 'API Support',
      url: 'https://github.com/oliban/anagram-game'
    },
    license: {
      name: 'MIT',
      url: 'https://opensource.org/licenses/MIT'
    }
  },
  host: 'localhost:3000',
  schemes: ['http'],
  consumes: ['application/json'],
  produces: ['application/json'],
  tags: [
    {
      name: 'Server Health',
      description: 'Server status and health monitoring'
    },
    {
      name: 'Player Management', 
      description: 'Player registration and online status'
    },
    {
      name: 'Phrase Management',
      description: 'Phrase creation, retrieval, and management'
    }
  ],
  definitions: {
    Player: {
      id: "123e4567-e89b-12d3-a456-426614174000",
      name: "John Doe",
      lastSeen: "2023-12-07T10:30:00.000Z",
      isActive: true,
      phrasesCompleted: 15
    },
    Phrase: {
      id: "123e4567-e89b-12d3-a456-426614174000",
      content: "Hello world",
      hint: "A greeting to the world",
      senderId: "123e4567-e89b-12d3-a456-426614174000",
      targetId: "456e7890-e89b-12d3-a456-426614174000",
      createdAt: "2023-12-07T10:30:00.000Z",
      isConsumed: false,
      difficultyLevel: 3,
      isGlobal: false
    },
    Error: {
      error: "Error message",
      timestamp: "2023-12-07T10:30:00.000Z"
    }
  },
  // Auto-detection settings
  autoQuery: true,
  autoBody: true,
  autoResponses: true,
  autoHeaders: true
};

const outputFile = './swagger-output.json';
const endpointsFiles = ['./server.js'];

console.log('🔄 Generating API documentation...');

swaggerAutogen(outputFile, endpointsFiles, doc).then(() => {
  console.log('✅ API documentation generated successfully!');
  console.log('📄 Output file: swagger-output.json');
  console.log('🌐 View at: http://localhost:3000/api/docs/');
  console.log('');
  console.log('💡 To regenerate docs after API changes:');
  console.log('   npm run docs');
});