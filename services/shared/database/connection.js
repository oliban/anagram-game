const { Pool } = require('pg');

// Database configuration
const dbConfig = {
  user: process.env.DB_USER || process.env.USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'anagram_game',
  password: process.env.DB_PASSWORD || '',
  port: process.env.DB_PORT || 5432,
  
  // Connection pool settings
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // How long a client is allowed to remain idle
  connectionTimeoutMillis: 10000, // How long to wait for a connection
  
  // SSL configuration - secure by default in production
  ssl: process.env.NODE_ENV === 'production' ? {
    rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
    // Optional: provide CA certificate if needed
    ca: process.env.DB_SSL_CA || undefined
  } : false
};

// Create connection pool
const pool = new Pool(dbConfig);

// Pool error handling
pool.on('error', (err, client) => {
  console.error('❌ DATABASE: Unexpected error on idle client', err);
  process.exit(-1);
});

// Pool connection event logging
pool.on('connect', (client) => {
  console.log('🔌 DATABASE: New client connected');
});

pool.on('acquire', (client) => {
  console.log('📋 DATABASE: Client acquired from pool');
});

pool.on('remove', (client) => {
  console.log('🗑️ DATABASE: Client removed from pool');
});

// Test database connection
async function testConnection() {
  try {
    const client = await pool.connect();
    const result = await client.query('SELECT NOW() as timestamp, version() as version');
    client.release();
    
    console.log('✅ DATABASE: Connection successful');
    console.log(`📅 DATABASE: Server time: ${result.rows[0].timestamp}`);
    console.log(`🔢 DATABASE: PostgreSQL version: ${result.rows[0].version.split(' ')[1]}`);
    
    return true;
  } catch (error) {
    console.error('❌ DATABASE: Connection failed:', error.message);
    return false;
  }
}

// Execute query with error handling
async function query(text, params = []) {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`📊 DATABASE: Query executed in ${duration}ms - ${result.rowCount} rows affected`);
      if (duration > 1000) {
        console.warn(`⚠️ DATABASE: Slow query detected (${duration}ms): ${text.substring(0, 100)}...`);
      }
    }
    
    return result;
  } catch (error) {
    console.error('❌ DATABASE: Query error:', error.message);
    console.error('📝 DATABASE: Query:', text);
    console.error('📋 DATABASE: Params:', params);
    throw error;
  }
}

// Execute transaction
async function transaction(callback) {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ DATABASE: Transaction rolled back:', error.message);
    throw error;
  } finally {
    client.release();
  }
}

// Get database statistics
async function getStats() {
  try {
    const result = await query(`
      SELECT 
        (SELECT COUNT(*) FROM phrases) as total_phrases,
        (SELECT COUNT(*) FROM phrases WHERE is_global = true AND is_approved = true) as global_phrases,
        (SELECT COUNT(*) FROM completed_phrases) as completed_phrases,
        (SELECT COUNT(*) FROM players WHERE is_active = true) as active_players,
        (SELECT COUNT(*) FROM player_phrases WHERE is_delivered = false) as pending_targeted_phrases
    `);
    
    return result.rows[0];
  } catch (error) {
    console.error('❌ DATABASE: Failed to get stats:', error.message);
    return {
      total_phrases: 0,
      global_phrases: 0,
      completed_phrases: 0,
      active_players: 0,
      pending_targeted_phrases: 0
    };
  }
}

// Graceful shutdown
async function shutdown() {
  try {
    await pool.end();
    console.log('✅ DATABASE: Connection pool closed');
  } catch (error) {
    console.error('❌ DATABASE: Error during shutdown:', error.message);
  }
}

// Handle process termination
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

module.exports = {
  pool,
  query,
  transaction,
  testConnection,
  getStats,
  shutdown
};