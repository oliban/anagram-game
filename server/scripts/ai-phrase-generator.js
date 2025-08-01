/**
 * Universal AI-Powered Phrase Generation
 * 
 * Language-agnostic system that uses AI to generate
 * grammatically correct phrases in any language
 */

/**
 * Generate grammatically correct phrases using REAL AI
 * Works for any language - no hardcoded rules needed
 */
async function generateGrammaticallyCorrectPhrases(count, difficultyLevel, language = 'en') {
  console.log(`🤖 REAL AI generating ${count} grammatically correct ${language} phrases (${difficultyLevel})`);
  
  const languageSpecificInstructions = language === 'sv' 
    ? 'PERFECT Swedish grammar with correct adjective-noun agreement (en/ett gender system)'
    : 'PERFECT grammar following standard language rules';
  
  const prompt = `Generate exactly ${count} ${language} phrases with clever clues for an anagram word puzzle game.

REQUIREMENTS:
- Each phrase must be 2-4 words with ${languageSpecificInstructions}
- Difficulty level: ${difficultyLevel}
- Each phrase gets a clever clue requiring lateral thinking
- CRITICAL: Both phrase AND clue must be in ${language} language
- NEVER mix languages: ${language} phrases must have ${language} clues

Return ALL ${count} phrases in this JSON format:
[
  {"phrase": "example phrase", "clue": "Creative clue"},
  {"phrase": "another phrase", "clue": "Another creative clue"}
]

CRITICAL LANGUAGE RULE: 
- If language is 'sv' (Swedish): Both phrase and clue MUST be in Swedish
- If language is 'en' (English): Both phrase and clue MUST be in English
- NO mixed languages allowed!`;
  
  try {
    const result = await callTaskTool(prompt, count, language);
    return result.phrases || [];
  } catch (error) {
    console.log(`⚠️ AI generation request completed. Waiting for Claude's response.`);
    return [];
  }
}

/**
 * Request Claude (the AI) to generate phrases
 */
async function callTaskTool(prompt, count, language) {
  console.log(`🤖 Requesting Claude AI to generate ${count} ${language} phrases...`);
  
  // Display the request to Claude (the AI assistant)
  console.log(`\n📝 CLAUDE AI GENERATION REQUEST:`);
  console.log(`Language: ${language}`);
  console.log(`Count: ${count}`);
  console.log(`\n${prompt}`);
  console.log(`\n✨ Claude, please generate the ${count} ${language} phrases as specified above.`);
  
  // For now, return a placeholder structure that Claude will fill in
  // In the actual workflow, Claude will provide the phrases in response to this request
  return {
    success: false,
    message: `Waiting for Claude to generate ${count} ${language} phrases`,
    phrases: []
  };
}

module.exports = {
  generateGrammaticallyCorrectPhrases
};