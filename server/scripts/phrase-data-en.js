/**
 * English phrase data with clever clues for AI simulation
 * Organized by difficulty levels for anagram game generation
 */

const englishPhraseData = {
  easy: [
    {phrase: 'cold winter', clue: 'Jack Frost\'s favorite season'},
    {phrase: 'warm sun', clue: 'Solar panel\'s best friend'},
    {phrase: 'bright star', clue: 'Navigator\'s ancient GPS'},
    {phrase: 'fresh air', clue: 'What city dwellers crave most'},
    {phrase: 'happy child', clue: 'Playground giggles source'},
    {phrase: 'calm lake', clue: 'Nature\'s perfect mirror'},
    {phrase: 'soft rain', clue: 'Umbrella\'s gentle reminder'},
    {phrase: 'sweet dream', clue: 'Pillow\'s gift to sleepers'},
    {phrase: 'kind heart', clue: 'Generosity\'s home address'},
    {phrase: 'blue sky', clue: 'Robin\'s egg ceiling'},
    {phrase: 'nice day', clue: 'Weather app\'s smiley face'},
    {phrase: 'dark night', clue: 'Stars\' time to shine'},
    {phrase: 'white snow', clue: 'Winter\'s blank canvas'},
    {phrase: 'green tree', clue: 'Squirrel\'s apartment building'},
    {phrase: 'good book', clue: 'Page turner\'s addiction'}
  ],
  medium: [
    {phrase: 'gentle breeze', clue: 'Curtain\'s dancing partner'},
    {phrase: 'magic forest', clue: 'Fairy tale\'s favorite setting'},
    {phrase: 'bright sunset', clue: 'Day\'s grand finale'},
    {phrase: 'quiet corner', clue: 'Introvert\'s sanctuary'},
    {phrase: 'warm coffee', clue: 'Morning ritual\'s liquid hug'},
    {phrase: 'golden light', clue: 'Photographer\'s holy grail'},
    {phrase: 'smooth stone', clue: 'River\'s polished artwork'},
    {phrase: 'deep ocean', clue: 'Whale\'s endless highway'},
    {phrase: 'clever trick', clue: 'Magician\'s secret weapon'},
    {phrase: 'happy family', clue: 'Holiday card\'s perfect picture'},
    {phrase: 'sweet melody', clue: 'Ear\'s favorite candy'},
    {phrase: 'brave knight', clue: 'Dragon\'s worthy opponent'},
    {phrase: 'secret garden', clue: 'Hidden paradise keeper'},
    {phrase: 'perfect moment', clue: 'Memory\'s treasure chest'},
    {phrase: 'inner peace', clue: 'Meditation\'s ultimate prize'}
  ],
  hard: [
    {phrase: 'system logic', clue: 'Computer\'s thinking pattern'},
    {phrase: 'neural path', clue: 'Brain\'s information highway'},
    {phrase: 'prime factor', clue: 'Mathematician\'s building block'},
    {phrase: 'data core', clue: 'Information\'s treasure chest'},
    {phrase: 'complex method', clue: 'PhD thesis requirement'},
    {phrase: 'unique format', clue: 'Snowflake\'s design principle'},
    {phrase: 'expert level', clue: 'Master\'s achievement tier'},
    {phrase: 'dynamic model', clue: 'Change\'s mathematical mirror'},
    {phrase: 'code frame', clue: 'Developer\'s skeleton key'},
    {phrase: 'logic tree', clue: 'Reasoning\'s family branches'},
    {phrase: 'data node', clue: 'Network\'s connection point'},
    {phrase: 'core system', clue: 'Operation\'s beating heart'},
    {phrase: 'method cache', clue: 'Speed\'s secret stash'},
    {phrase: 'format theory', clue: 'Structure\'s guiding principle'},
    {phrase: 'atomic level', clue: 'Microscope\'s deepest dive'}
  ],
  expert: [
    {phrase: 'quantum flux', clue: 'Physics professor\'s headache'},
    {phrase: 'neural matrix', clue: 'AI\'s thinking blueprint'},
    {phrase: 'crypto hash', clue: 'Digital fingerprint maker'},
    {phrase: 'binary tree', clue: 'Computer science\'s family tree'},
    {phrase: 'plasma field', clue: 'Lightning\'s energy playground'},
    {phrase: 'cyber space', clue: 'Internet\'s invisible dimension'},
    {phrase: 'nano tech', clue: 'Microscopic engineering marvel'},
    {phrase: 'matrix core', clue: 'Reality\'s control center'},
    {phrase: 'flux wave', clue: 'Energy\'s dancing rhythm'},
    {phrase: 'mesh grid', clue: 'Network\'s invisible web'},
    {phrase: 'beam pulse', clue: 'Light\'s heartbeat signal'},
    {phrase: 'node space', clue: 'Connection\'s meeting point'},
    {phrase: 'hash tree', clue: 'Security\'s branching fortress'},
    {phrase: 'wave field', clue: 'Frequency\'s vast ocean'},
    {phrase: 'tech core', clue: 'Innovation\'s beating heart'}
  ]
};

module.exports = englishPhraseData;