#!/usr/bin/env node

/**
 * Generate up-to-date Swagger API documentation
 * Scans all route files and generates comprehensive OpenAPI spec
 */

const swaggerAutogen = require('swagger-autogen')();
const path = require('path');

const outputFile = './shared/swagger-output.json';

// All route files to scan
const endpointsFiles = [
  './game-server/routes/players.js', 
  './game-server/routes/phrases.js',
  './game-server/routes/leaderboards.js',
  './game-server/routes/contributions.js'
];

// Enhanced Swagger configuration
const doc = {
  info: {
    version: '2.0.0',
    title: 'Wordshelf Multiplayer API',
    description: `
      Comprehensive API for Wordshelf multiplayer word game server.
      
      ## Features
      - **Player Management**: Registration, authentication, online status
      - **Phrase System**: Create, retrieve, complete custom and global phrases  
      - **Real-time Communication**: WebSocket support for multiplayer features
      - **Scoring & Leaderboards**: Advanced scoring system with multiple leaderboard types
      - **Security**: Rate limiting, input validation, CORS protection
      - **Multi-language Support**: English and Swedish phrase support
      
      ## Environment Configuration
      - **Development**: http://192.168.1.188:3000 (local development server)
      - **Staging**: https://unfortunately-versions-assumed-threat.trycloudflare.com (Pi staging with Cloudflare)  
      - **Production**: http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com (AWS production)
      
      ## Authentication
      Some endpoints require API key authentication via X-API-Key header.
      
      ## Rate Limits
      - General API: 120 requests/15min (dev), 30 requests/15min (prod)
      - Sensitive endpoints: 100 requests/15min (dev), 10 requests/15min (prod)
      
      ## WebSocket Events
      - **Game namespace** (/): Open for all clients
      - **Monitoring namespace** (/monitoring): Requires API key authentication
    `,
    contact: {
      name: 'Wordshelf API Support',
      email: 'support@wordshelf.com'
    },
    license: {
      name: 'MIT',
      url: 'https://opensource.org/licenses/MIT'
    }
  },
  host: process.env.SWAGGER_HOST || '192.168.1.188:3000',
  schemes: ['http', 'https'],
  consumes: ['application/json'],
  produces: ['application/json'],
  
  // Security definitions
  securityDefinitions: {
    ApiKeyAuth: {
      type: 'apiKey',
      in: 'header',
      name: 'X-API-Key',
      description: 'API key for admin endpoints'
    }
  },
  
  // Global tags
  tags: [
    {
      name: 'System',
      description: 'Server health and configuration endpoints'
    },
    {
      name: 'Players',
      description: 'Player registration, authentication, and management'
    },
    {
      name: 'Phrases',
      description: 'Phrase creation, retrieval, completion, and management'
    },
    {
      name: 'Leaderboards', 
      description: 'Player rankings and scoring statistics'
    },
    {
      name: 'Contributions',
      description: 'Community phrase contribution system'
    },
    {
      name: 'Debug',
      description: 'Development and debugging utilities'
    },
    {
      name: 'Admin',
      description: 'Administrative operations (requires API key)'
    }
  ],
  
  // Common response schemas
  definitions: {
    Error: {
      type: 'object',
      properties: {
        error: {
          type: 'string',
          description: 'Error message'
        },
        details: {
          type: 'array',
          items: {
            type: 'object'
          },
          description: 'Detailed error information'
        }
      },
      required: ['error']
    },
    
    Player: {
      type: 'object',
      properties: {
        id: {
          type: 'string',
          format: 'uuid',
          description: 'Unique player identifier'
        },
        name: {
          type: 'string',
          minLength: 1,
          maxLength: 50,
          pattern: '^[a-zA-Z0-9\\s\\-_åäöÅÄÖ]{1,50}$',
          description: 'Player display name'
        },
        isOnline: {
          type: 'boolean',
          description: 'Current online status'
        },
        language: {
          type: 'string',
          enum: ['en', 'sv'],
          description: 'Player preferred language'
        },
        createdAt: {
          type: 'string',
          format: 'date-time',
          description: 'Account creation timestamp'
        },
        totalScore: {
          type: 'integer',
          minimum: 0,
          description: 'Total accumulated score'
        }
      },
      required: ['id', 'name', 'isOnline']
    },
    
    Phrase: {
      type: 'object',
      properties: {
        id: {
          type: 'integer',
          description: 'Unique phrase identifier'
        },
        content: {
          type: 'string',
          minLength: 1,
          maxLength: 500,
          pattern: '^[a-zA-Z0-9\\s\\-_.,!?\'\"()åäöÅÄÖ]*$',
          description: 'The phrase text to unscramble'
        },
        hint: {
          type: 'string',
          maxLength: 1000,
          description: 'Optional hint for the phrase'
        },
        language: {
          type: 'string',
          enum: ['en', 'sv'],
          description: 'Phrase language'
        },
        difficultyLevel: {
          type: 'integer',
          minimum: 1,
          maximum: 100,
          description: 'Calculated difficulty level'
        },
        senderName: {
          type: 'string',
          description: 'Name of player who sent this phrase'
        },
        isGlobal: {
          type: 'boolean',
          description: 'Whether phrase is available globally'
        },
        createdAt: {
          type: 'string',
          format: 'date-time',
          description: 'Creation timestamp'
        }
      },
      required: ['id', 'content', 'language', 'difficultyLevel']
    },
    
    LeaderboardEntry: {
      type: 'object',
      properties: {
        playerId: {
          type: 'string',
          format: 'uuid'
        },
        playerName: {
          type: 'string'
        },
        score: {
          type: 'integer',
          minimum: 0
        },
        rank: {
          type: 'integer',
          minimum: 1
        }
      },
      required: ['playerId', 'playerName', 'score', 'rank']
    }
  }
};

// Generate the documentation
console.log('🔄 Generating Swagger documentation...');
console.log(`📁 Output file: ${outputFile}`);
console.log(`📂 Scanning ${endpointsFiles.length} route files:`);
endpointsFiles.forEach(file => console.log(`   - ${file}`));

swaggerAutogen(outputFile, endpointsFiles, doc).then(() => {
  console.log('✅ Swagger documentation generated successfully!');
  console.log(`📖 View documentation at: http://192.168.1.188:3000/api-docs`);
  
  // Also copy to the old server location for compatibility
  const fs = require('fs');
  const oldPath = '../../server/swagger-output.json';
  try {
    fs.copyFileSync(outputFile, oldPath);
    console.log('📋 Copied to legacy server location for compatibility');
  } catch (err) {
    console.log('⚠️  Could not copy to legacy location:', err.message);
  }
}).catch(err => {
  console.error('❌ Error generating Swagger documentation:', err);
  process.exit(1);
});