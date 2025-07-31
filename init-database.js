// Quick database initialization script
const { Client } = require('pg');
const fs = require('fs');

const client = new Client({
  host: 'anagramstagingstack-anagramdatabase339d2f6a-4rmodxfr7xfe.cluster-ct6uiwk22amy.eu-west-1.rds.amazonaws.com',
  port: 5432,
  database: 'anagram_game',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
});

async function initDatabase() {
  try {
    await client.connect();
    console.log('Connected to database');
    
    // Check if players table exists
    const result = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'players'
      );
    `);
    
    if (!result.rows[0].exists) {
      console.log('Creating players table...');
      
      // Create minimal players table for testing
      await client.query(`
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
        
        CREATE TABLE players (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          name VARCHAR(50) NOT NULL,
          device_id VARCHAR(255) NOT NULL,
          is_active BOOLEAN DEFAULT true,
          last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          phrases_completed INTEGER DEFAULT 0,
          socket_id VARCHAR(255) NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(name, device_id)
        );
      `);
      
      console.log('Players table created successfully!');
    } else {
      console.log('Players table already exists');
    }
    
  } catch (error) {
    console.error('Database initialization error:', error);
  } finally {
    await client.end();
  }
}

initDatabase();