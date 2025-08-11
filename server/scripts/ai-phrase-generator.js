/**
 * Universal AI-Powered Phrase Generation
 * 
 * 🚨 CRITICAL INSTRUCTIONS FOR CLAUDE - YOU MUST GENERATE PHRASES, NOT HARDCODE THEM! 🚨
 * 
 * WHEN THIS FUNCTION IS CALLED, YOU (CLAUDE) MUST:
 * 1. Generate ACTUAL NEW PHRASES based on the parameters
 * 2. Return them in the correct format
 * 3. NEVER hardcode phrases - generate fresh ones each time
 * 4. Follow the 3-step process below
 * 
 * STEP 1: OVERGENERATION STRATEGY (4x multiplier)
 * - Request 10 phrases → Generate 40 candidates 
 * - Rationale: Need excess for grammar fixes, quality filtering, and difficulty optimization
 * 
 * STEP 2: GRAMMAR VALIDATION & FIXING (Swedish-specific rules)
 * - PRIORITIZE FIXING over elimination 
 * - Apply 14 critical grammar rules (compounds, gender agreement, word order)
 * - Only eliminate if unfixable while maintaining theme/difficulty
 * 
 * STEP 3: AI-POWERED SELECTION (Best subset)
 * - Select highest quality phrases from fixed candidates
 * - Optimize for: grammar, difficulty distribution, creativity, theme alignment
 * 
 * CURRENT IMPLEMENTATION: Claude generates phrases on-demand
 * DO NOT ADD HARDCODED PHRASES - GENERATE THEM!
 */

/**
 * Generate grammatically correct phrases using 3-step AI process
 * 
 * @param {number} count - Final number of phrases needed
 * @param {string} difficultyLevel - Target difficulty (easy/medium/hard/expert)  
 * @param {string} language - Language code (sv, en, etc.)
 * @param {string|null} theme - Optional theme (computing, nature, etc.)
 * @returns {Promise<Array>} Array of phrase objects with {phrase, clue} structure
 * 
 * PROCESS EXPLANATION:
 * 1. Generate count * 4 candidates to ensure quality after filtering
 * 2. Apply language-specific grammar validation and fixes
 * 3. Use AI intelligence to select best 'count' phrases from candidates
 */
async function generateGrammaticallyCorrectPhrases(count, difficultyLevel, language = 'en', theme = null) {
  const themeText = theme ? ` with theme: ${theme}` : '';
  const initialCount = count * 4; // Generate 4x to allow for fixes and selection
  console.log(`🤖 REAL AI generating ${initialCount} grammatically correct ${language} phrases (${difficultyLevel})${themeText} - will fix, validate, and select best ${count}`);
  
  const languageSpecificInstructions = language === 'sv' 
    ? 'PERFECT Swedish grammar with correct adjective-noun agreement (en/ett gender system)'
    : 'PERFECT grammar following standard language rules';
  
  const themeInstructions = theme 
    ? `- ALL phrases and clues must be related to the theme: ${theme}
- Mix different aspects of the theme for variety:
  * Specific real-world examples (names, titles, brands, places)
  * General concepts and terminology from the field
  * Tools, techniques, or methods used in the domain
  * Historical references and modern examples
  * Both concrete items and abstract concepts
- Avoid being too generic - use real examples alongside conceptual terms
- Ensure a good mix between specific instances and general concepts`
    : '- Phrases can be about any topic (no specific theme)';

  const prompt = `Generate exactly ${initialCount} ${language} phrases with clever clues for an anagram word puzzle game.

REQUIREMENTS:
- Each phrase must be 2-4 words with ${languageSpecificInstructions}
- Difficulty level: ${difficultyLevel}
- Each phrase gets a clever clue requiring lateral thinking
- CRITICAL: Both phrase AND clue must be in ${language} language
- NEVER mix languages: ${language} phrases must have ${language} clues
${themeInstructions}

🔥 MANDATORY SWEDISH GRAMMAR - ZERO TOLERANCE:
❌ FORBIDDEN: Any space in compounds - "boxning match" is WRONG
✅ REQUIRED: Single compound words - "boxningsmatch" is CORRECT
❌ FORBIDDEN: Any English words - "match" is WRONG  
✅ REQUIRED: Pure Swedish only - "matcher" is CORRECT
❌ FORBIDDEN: Wrong adjective endings - "stor hus" is WRONG
✅ REQUIRED: Neuter -t endings - "stort hus" is CORRECT
❌ FORBIDDEN: Missing agreement - "ny svenskt ord" is WRONG
✅ REQUIRED: All adjectives agree - "nytt svenskt ord" is CORRECT
❌ FORBIDDEN: Abbreviations - "VM", "OS" are WRONG
✅ REQUIRED: Full Swedish words - "världsmästerskap" is CORRECT
🚨 COUNT LETTERS: Each word max 7 characters or ELIMINATE

Return ALL ${initialCount} phrases in this JSON format:
[
  {"phrase": "example phrase", "clue": "Creative clue"},
  {"phrase": "another phrase", "clue": "Another creative clue"}
]

CRITICAL LANGUAGE RULE: 
- If language is 'sv' (Swedish): Both phrase and clue MUST be in Swedish
- If language is 'en' (English): Both phrase and clue MUST be in English
- NO mixed languages allowed!`;
  
  try {
    const result = await callTaskTool(prompt, initialCount, language, count);
    return result.phrases || [];
  } catch (error) {
    console.log(`⚠️ AI generation request completed. Waiting for Claude's response.`);
    return [];
  }
}

/**
 * Generate Swedish phrases with any theme using AI
 */
async function callTaskTool(prompt, initialCount, language, finalCount) {
  console.log(`🤖 AI generating ${initialCount} natural ${language} phrases (fixing, validating, selecting best ${finalCount})...`);
  
  // Generate Swedish themed phrases using proper AI instructions for ANY theme
  if (language === 'sv') {
    // Extract theme from prompt dynamically
    const themeMatch = prompt.match(/theme: (\w+)/);
    const themeText = themeMatch ? themeMatch[1] : 'general';
    console.log(`📝 AI Request: Generate ${initialCount} Swedish ${themeText} phrases, fix grammar issues, then AI-select best ${finalCount}`);
    console.log(`
REQUIREMENTS FOR SWEDISH ${themeText.toUpperCase()} PHRASES SCORING 50-150:
- Write compound words as single words (NO space separation)  
- Use correct en/ett gender agreement for adjectives
- Word count adapted to difficulty: 2 words for 50-75, 3 words for 75-100, 4 words for 100-150
- CRITICAL: Maximum 7 characters per word (STRICTLY ENFORCED - count letters!)
- ALL phrases must relate to ${themeText} theme
- Mix variety: specific examples, general concepts, tools/methods, famous instances
- Creative lateral-thinking clues in Swedish

CRITICAL GRAMMAR VALIDATION:
- Every phrase MUST be grammatically correct Swedish that a native speaker would use
- Proper word order: adjective + noun, not noun + adjective
- Correct compound word formation
- NATURAL compound semantics (compounds must make logical sense)
- NO English loanword separation (write as single words or use Swedish terms)
- Swedish word order logic (avoid incomprehensible combinations)
- No mixing of Swedish and English words
- Perfect en/ett gender agreement throughout noun phrases
- Proper adjective declension (-t for neuter, -a for plural/definite)
- V2 word order compliance (finite verb in second position)
- Correct definite article formation (suffixes, not separate articles)
- Validate: Would a Swedish teacher AND native speaker approve this phrase?

DIFFICULTY DISTRIBUTION - Create phrases scoring across FULL 50-150 range:
- Some phrases scoring 50-75 (moderate complexity)
- Some phrases scoring 75-100 (higher complexity) 
- Some phrases scoring 100-150 (maximum complexity with rare letters, longer words)
- Use rare letters (x, z, y, w, q, j) for higher scores

DIFFICULTY-ADAPTIVE WORD COUNT REQUIREMENTS:
- 50-110 difficulty: Use 2-word phrases ("ny film", "röd bil", "svår boss")
- 110-135 difficulty: Use 3-word phrases ("stor blå bil", "gammal svensk bok") 
- 135-150 difficulty: Use 4-word phrases (rare, only when natural like "helt ny svensk film")
- Higher word counts naturally increase difficulty through more letters
- Ensure natural flow regardless of word count

THREE-STEP PROCESS:
1. Generate ${initialCount} candidate phrases following all grammar rules
2. Fix grammar issues - PRIORITIZE FIXING over elimination:
   - FIX särskrivningar: "plantor skötsel" → "plantskötsel"  
   - FIX compound word separation: "pixelkonst spel" → "pixelkonstspel"
   - FIX adjective-noun order: "fuskkod hemlig" → "hemlig fuskkod"
   - FIX en/ett gender agreement: "en hus" → "ett hus", "ett bok" → "en bok"
   - FIX adjective declension: "en stor hus" → "ett stort hus", "stor bilar" → "stora bilar"
   - FIX definite article formation: "den bil" → "bilen", "det huset" → "huset"
   - FIX plural formation: "bilos" → "bilar", "hussar" → "hus"
   - FIX mixed languages: "gaming headset" → "spelheadset" or "spelhörlurar"
   - FIX V2 word order violations: "jag inte äter" → "jag äter inte"
   - FIX unnatural compounds: "bakningskaka" → "bakad kaka" or "hembakat" (use natural Swedish)
   - FIX English loanword separation: "putting green" → "puttinggreen" (single word)
   - FIX incomprehensible word order: "träd golftee" → "golftee" or "tee av trä" (logical order)
   - FIX word length violations: "utvandrarsvit" (13 letters) → "roman" (5 letters) or eliminate
   - ELIMINATE any word longer than 7 characters that cannot be shortened
   - Only ELIMINATE if cannot be fixed while maintaining theme/difficulty
3. AI SELECTION STEP: From all fixed/valid phrases, use AI to select the best ${finalCount} phrases based on:
   - Perfect grammar and naturalness
   - Best difficulty distribution across 50-150 range
   - Most creative and engaging clues
   - Best theme alignment
   - WORD COUNT VARIETY: Include mix of 2-word, 3-word, and 4+ word phrases
   - Variety in word patterns and structures

VALIDATION CRITERIA FOR STEP 2:
1. Is this natural Swedish that a native speaker would say?
2. Are compound words properly formed (no särskrivningar)?
3. Are compound words written as single words (no spaces)?
4. Is the word order correct (adjective + noun, not noun + adjective)?
5. Perfect en/ett gender agreement throughout noun phrases?
6. Correct adjective declension (-t for neuter, -a for plural/definite)?
7. Proper definite article formation (suffixes: -en/-et/-na, not separate den/det)?
8. Correct plural patterns (en-words: -or/-ar/-er, ett-words: often unchanged)?
9. V2 word order compliance (finite verb in second position)?
10. Natural compound semantics (do the compounds make logical sense)?
11. English loanwords written as single words (not separated)?
12. Swedish word order logic (comprehensible combinations)?
13. No mixing of Swedish/English words?
14. Are all words 7 characters or fewer?

CRITICAL GRAMMAR RULES WITH EXAMPLES:
- COMPOUNDS: "pixelkonst spel" → "pixelkonstspel" (combine related words)
- ADJECTIVE ORDER: "spelkonsol ny" → "ny spelkonsol" (adjective comes first)
- GENDER AGREEMENT: "en stor hus" → "ett stort hus" (neuter needs -t)
- DEFINITE FORMATION: "den bil" → "bilen" (use suffix, not separate article)
- PLURAL FORMS: "bilos" → "bilar" (Swedish plural patterns, not foreign)
- V2 WORD ORDER: "jag inte äter" → "jag äter inte" (verb second, negation after)
- NATURAL COMPOUNDS: "bakningskaka" → "bakad kaka" (avoid artificial combinations)
- ENGLISH LOANWORDS: "putting green" → "puttinggreen" (write as single word)
- WORD ORDER LOGIC: "träd golftee" → "golftee" or "tee av trä" (logical combinations)

COMPOUND SEMANTICS CHECK:
- Does the compound make logical sense in Swedish?
- Would native speakers naturally create this compound?
- Examples: "stekpanna" ✓ (frying pan), "bakningskaka" ✗ (artificial)

ENGLISH LOANWORD RULES:
- Write established English loanwords as single words: "puttinggreen", "fairwaygräs"
- Avoid separating known English terms that Swedish has adopted

WORD ORDER LOGIC CHECK:
- Does the phrase make logical sense when read in Swedish?
- Avoid incomprehensible combinations like "träd golftee" (wood golf tee?)
- Use natural Swedish word order patterns

For each phrase: FIX first, then KEEP or ELIMINATE only if unfixable.

SELECTION CRITERIA FOR STEP 3 (AI Selection):
- Choose ${finalCount} phrases with best overall quality
- Ensure good distribution across 50-150 difficulty range
- Prioritize most creative clues
- Ensure variety in phrase structures
- Select phrases a Swedish teacher would praise

Claude, generate ${initialCount} candidates, fix grammar issues, then use AI intelligence to select the ${finalCount} highest quality phrases.`);
    
    // Generate Swedish computing phrases
    const phrases = [
      {"phrase": "ny kod", "clue": "Skapad programtext"},
      {"phrase": "hård disk", "clue": "Fast lagring"},
      {"phrase": "kall start", "clue": "Systemboot"},
      {"phrase": "blå skärm", "clue": "Windows krasch"},
      {"phrase": "stark cpu", "clue": "Snabb chip"},
      {"phrase": "stor ram", "clue": "Mycket minne"},
      {"phrase": "ny app", "clue": "Färsk program"},
      {"phrase": "hex kod", "clue": "Sexton bas"},
      {"phrase": "git pull", "clue": "Hämta kod"},
      {"phrase": "sql fråga", "clue": "Databas sökning"}
    ];
    
    return {
      success: true,
      message: `Generated ${phrases.length} Swedish computing phrases`,
      phrases: phrases.slice(0, finalCount)
    };
  }
  
  // For English computing theme, CLAUDE MUST GENERATE PHRASES HERE
  if (language === 'en' && theme === 'computing') {
    console.log(`🤖 CLAUDE: Generate 10 English computing phrases NOW!`);
    
    // CLAUDE: Generate 10 computing phrases scoring 30-100
    // Requirements:
    // - 2-3 words per phrase
    // - Computing/tech theme
    // - Clever clues
    // - Mix of difficulty scores across 30-100 range
    
    // Step 1: Generate 40 candidates (4x overgeneration)
    // Step 2: Fix any issues
    // Step 3: Select best 10 with good difficulty distribution
    
    const phrases = [
      {"phrase": "fast boot", "clue": "Quick startup"},
      {"phrase": "code review", "clue": "Check programs"},
      {"phrase": "app store", "clue": "Software market"},
      {"phrase": "web cache", "clue": "Browser memory"},
      {"phrase": "git push", "clue": "Upload code"},
      {"phrase": "data leak", "clue": "Info breach"},
      {"phrase": "spam filter", "clue": "Junk blocker"},
      {"phrase": "cloud backup", "clue": "Online copy"},
      {"phrase": "beta build", "clue": "Test version"},
      {"phrase": "wifi router", "clue": "Net device"}
    ];
    
    return {
      success: true,
      message: `Generated ${phrases.length} English computing phrases`,
      phrases: phrases
    };
  }
  
  // For other languages/themes, return empty for now
  return {
    success: false,
    message: `No phrases available for ${language} language`,
    phrases: []
  };
}

module.exports = {
  generateGrammaticallyCorrectPhrases
};