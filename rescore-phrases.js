const {Client} = require("pg");
const { calculateScore } = require("./shared/difficulty-algorithm.js");

async function rescoreAllPhrases() {
  const client = new Client({host: "postgres", database: "anagram_game", user: "postgres", password: "postgres"});
  await client.connect();
  
  console.log("🔄 Re-scoring all phrases with difficulty = 1...");
  
  try {
    await client.query("BEGIN");
    
    const result = await client.query("SELECT id, content, language FROM phrases WHERE difficulty_level = 1;");
    console.log(`Found ${result.rows.length} phrases to re-score`);
    
    let updated = 0;
    for (const row of result.rows) {
      try {
        const score = calculateScore({phrase: row.content, language: row.language});
        await client.query("UPDATE phrases SET difficulty_level = $1 WHERE id = $2", [score, row.id]);
        updated++;
        if (updated % 20 === 0) console.log(`✅ Updated ${updated} phrases...`);
      } catch (err) {
        console.log(`❌ Failed to score: ${row.content} - ${err.message}`);
      }
    }
    
    await client.query("COMMIT");
    console.log(`🎯 Re-scoring complete: ${updated} phrases updated`);
    
  } catch (err) {
    await client.query("ROLLBACK");
    console.log("❌ Transaction failed:", err.message);
  }
  
  await client.end();
}

rescoreAllPhrases().catch(e => console.log("Error:", e.message));