// Parse command line arguments
const args = process.argv.slice(2);

// Check for help flag first
if (args.includes('--help') || args.includes('-h')) {
  console.log(`
📊 Phrase Count Analysis Script

Usage:
  node phrase-count-detailed.js [environment] [staging-host]

Arguments:
  environment    Database environment: 'local' or 'staging' (default: local)
  staging-host   IP address for staging database (default: 192.168.1.222)

Examples:
  node phrase-count-detailed.js                    # Local database
  node phrase-count-detailed.js staging            # Staging with default Pi IP
  node phrase-count-detailed.js staging 10.0.0.5  # Staging with custom IP

Output:
  - Cross-tabulation table with themes as rows, languages as columns
  - Summary by theme
  - Summary by language
  - Total phrase count
`);
  process.exit(0);
}

const environment = args[0] || 'local';
const stagingHost = args[1]; // Optional staging host IP

// Database configuration based on environment
let dbConfig;
if (environment === 'staging') {
  const host = stagingHost || '192.168.1.222'; // Default Pi staging IP
  console.log(`🌐 Connecting to staging database at ${host}...`);
  
  // Create staging database connection
  const { Pool } = require('pg');
  const pool = new Pool({
    host: host,
    port: 5432,
    database: 'anagram_game',
    user: 'postgres',
    password: 'postgres',
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
  });
  
  // Custom query function for staging
  const query = async (text, params) => {
    const client = await pool.connect();
    try {
      const result = await client.query(text, params);
      return result;
    } finally {
      client.release();
    }
  };
  
  dbConfig = { query, pool };
} else {
  console.log('🏠 Connecting to local database...');
  // Use existing local connection
  const { query } = require('./database/connection');
  dbConfig = { query };
}

(async () => {
  try {
    console.log(`📊 Analyzing phrases in ${environment.toUpperCase()} database...\n`);
    
    // Create a cross-tabulation of themes vs languages with difficulty stats
    const result = await dbConfig.query(`
      SELECT 
        COALESCE(theme, 'null') as theme,
        SUM(CASE WHEN COALESCE(language, 'unknown') = 'en' THEN 1 ELSE 0 END) as english,
        SUM(CASE WHEN COALESCE(language, 'unknown') = 'sv' THEN 1 ELSE 0 END) as swedish,
        ROUND(AVG(difficulty_level), 1) as avg_difficulty,
        MIN(difficulty_level) as min_difficulty,
        MAX(difficulty_level) as max_difficulty
      FROM phrases 
      GROUP BY theme 
      ORDER BY COUNT(*) DESC
    `);
    
    console.log('📊 Phrases by theme (with language columns):');
    console.table(result.rows);
    
    // Summary by theme
    const themeResult = await dbConfig.query(`
      SELECT 
        COALESCE(theme, 'null') as theme,
        COUNT(*) as count 
      FROM phrases 
      GROUP BY theme 
      ORDER BY count DESC
    `);
    
    console.log('\n📈 Summary by theme:');
    console.table(themeResult.rows);
    
    // Summary by language  
    const langResult = await dbConfig.query(`
      SELECT 
        COALESCE(language, 'unknown') as language,
        COUNT(*) as count 
      FROM phrases 
      GROUP BY language 
      ORDER BY count DESC
    `);
    
    console.log('\n🌍 Summary by language:');
    console.table(langResult.rows);
    
    const total = await dbConfig.query('SELECT COUNT(*) as total FROM phrases');
    console.log('\n📈 Total phrases:', total.rows[0].total);
    
    // Difficulty distribution
    const difficultyDist = await dbConfig.query(`
      SELECT 
        CASE 
          WHEN difficulty_level < 20 THEN '0-19 (Very Easy)'
          WHEN difficulty_level < 40 THEN '20-39 (Easy)'
          WHEN difficulty_level < 60 THEN '40-59 (Medium)'
          WHEN difficulty_level < 80 THEN '60-79 (Hard)'
          WHEN difficulty_level < 100 THEN '80-99 (Very Hard)'
          ELSE '100+ (Extreme)'
        END as difficulty_range,
        COUNT(*) as count,
        ROUND(AVG(difficulty_level), 1) as avg_score
      FROM phrases
      WHERE difficulty_level IS NOT NULL
      GROUP BY 
        CASE 
          WHEN difficulty_level < 20 THEN '0-19 (Very Easy)'
          WHEN difficulty_level < 40 THEN '20-39 (Easy)'
          WHEN difficulty_level < 60 THEN '40-59 (Medium)'
          WHEN difficulty_level < 80 THEN '60-79 (Hard)'
          WHEN difficulty_level < 100 THEN '80-99 (Very Hard)'
          ELSE '100+ (Extreme)'
        END
      ORDER BY MIN(difficulty_level)
    `);
    
    console.log('\n📊 Difficulty Distribution:');
    console.table(difficultyDist.rows);
    
    // Overall difficulty stats
    const diffStats = await dbConfig.query(`
      SELECT 
        ROUND(AVG(difficulty_level), 1) as avg_difficulty,
        MIN(difficulty_level) as min_difficulty,
        MAX(difficulty_level) as max_difficulty,
        ROUND(STDDEV(difficulty_level), 1) as std_deviation,
        COUNT(*) as scored_phrases,
        COUNT(CASE WHEN difficulty_level IS NULL THEN 1 END) as unscored_phrases
      FROM phrases
    `);
    
    console.log('\n📈 Overall Difficulty Statistics:');
    console.table(diffStats.rows);
    
    // Close staging connection if used
    if (environment === 'staging' && dbConfig.pool) {
      await dbConfig.pool.end();
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Database error:', error);
    
    // Close staging connection on error if used
    if (environment === 'staging' && dbConfig.pool) {
      try {
        await dbConfig.pool.end();
      } catch (closeError) {
        console.error('❌ Error closing staging connection:', closeError.message);
      }
    }
    
    process.exit(1);
  }
})();