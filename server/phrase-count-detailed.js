const { query } = require('./database/connection');

(async () => {
  try {
    // Create a cross-tabulation of themes vs languages
    const result = await query(`
      SELECT 
        COALESCE(theme, 'null') as theme,
        SUM(CASE WHEN COALESCE(language, 'unknown') = 'en' THEN 1 ELSE 0 END) as english,
        SUM(CASE WHEN COALESCE(language, 'unknown') = 'sv' THEN 1 ELSE 0 END) as swedish,
        SUM(CASE WHEN COALESCE(language, 'unknown') NOT IN ('en', 'sv') THEN 1 ELSE 0 END) as other,
        COUNT(*) as total
      FROM phrases 
      GROUP BY theme 
      ORDER BY COUNT(*) DESC
    `);
    
    console.log('📊 Phrases by theme (with language columns):');
    console.table(result.rows);
    
    // Summary by theme
    const themeResult = await query(`
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
    const langResult = await query(`
      SELECT 
        COALESCE(language, 'unknown') as language,
        COUNT(*) as count 
      FROM phrases 
      GROUP BY language 
      ORDER BY count DESC
    `);
    
    console.log('\n🌍 Summary by language:');
    console.table(langResult.rows);
    
    const total = await query('SELECT COUNT(*) as total FROM phrases');
    console.log('\n📈 Total phrases:', total.rows[0].total);
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Database error:', error);
    process.exit(1);
  }
})();