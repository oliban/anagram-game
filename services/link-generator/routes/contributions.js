const express = require('express');
const path = require('path');
const router = express.Router();

module.exports = (dependencies) => {
  const { linkGenerator, pool, levelConfig } = dependencies;

  // Helper function to get player level from score
  function getPlayerLevel(totalScore) {
    let level = levelConfig.skillLevels[0];
    
    for (const skillLevel of levelConfig.skillLevels) {
      if (totalScore >= skillLevel.pointsRequired) {
        level = skillLevel;
      } else {
        break;
      }
    }
    
    return level;
  }

  // Helper function to get next level info
  function getNextLevelInfo(currentLevel) {
    const nextLevelId = currentLevel.id + 1;
    const nextLevel = levelConfig.skillLevels.find(level => level.id === nextLevelId);
    
    if (!nextLevel) {
      return { isMaxLevel: true };
    }
    
    return {
      isMaxLevel: false,
      nextLevel: nextLevel,
      pointsNeeded: nextLevel.pointsRequired - 0 // Will be calculated with actual player score
    };
  }

  // Helper function to get optimal difficulty range for a player level
  function getOptimalDifficultyRange(playerLevel) {
    const levelId = playerLevel.id;
    const maxDifficulty = playerLevel.maxDifficulty;
    
    // Suggest difficulty range: 60-90% of max difficulty for good challenge
    const minRecommended = Math.max(1, Math.floor(maxDifficulty * 0.6));
    const maxRecommended = Math.floor(maxDifficulty * 0.9);
    
    return {
      min: minRecommended,
      max: maxRecommended,
      playerMaxDifficulty: maxDifficulty,
      levelTitle: playerLevel.title
    };
  }

  // Serve contribution page
  router.get('/contribute/:token', (req, res) => {
    res.sendFile(path.join(__dirname, '../public', 'contribute', 'index.html'));
  });

  // Get contribution link details with REAL player data (for the web page)
  router.get('/api/contribution/:token', async (req, res) => {
    try {
      const { token } = req.params;
      console.log(`🔍 CONTRIB: Looking up contribution token: ${token}`);
      
      const validation = await linkGenerator.validateToken(token);
      
      if (!validation.valid) {
        console.log(`❌ CONTRIB: Token validation failed: ${validation.reason}`);
        return res.status(400).json({ 
          success: false, 
          error: validation.reason 
        });
      }

      const link = validation.link;
      console.log(`✅ CONTRIB: Found link for player: ${link.requestingPlayerName}`);
      
      // Get player score data from database
      const scoreQuery = `
        SELECT COALESCE(SUM(cp.score), 0) as total_score
        FROM completed_phrases cp
        WHERE cp.player_id = $1
      `;
      const scoreResult = await pool.query(scoreQuery, [link.requestingPlayerId]);
      const totalScore = scoreResult.rows[0]?.total_score || 0;
      
      console.log(`📊 CONTRIB: Player ${link.requestingPlayerName} has ${totalScore} points`);
      
      // Calculate player level and progression info
      const playerLevel = getPlayerLevel(totalScore);
      const nextLevelInfo = getNextLevelInfo(playerLevel);
      const optimalDifficulty = getOptimalDifficultyRange(playerLevel);
      
      console.log(`🏆 CONTRIB: Player level: ${playerLevel.title} (Level ${playerLevel.id})`);
      console.log(`🎯 CONTRIB: Optimal difficulty range: ${optimalDifficulty.min}-${optimalDifficulty.max}`);
      
      let progressionInfo = {};
      if (nextLevelInfo.isMaxLevel) {
        progressionInfo = {
          isMaxLevel: true,
          message: `${link.requestingPlayerName} has reached the highest level: ${playerLevel.title}!`
        };
      } else {
        const pointsNeeded = nextLevelInfo.nextLevel.pointsRequired - totalScore;
        progressionInfo = {
          isMaxLevel: false,
          currentLevel: playerLevel,
          nextLevel: nextLevelInfo.nextLevel,
          pointsNeeded: pointsNeeded,
          progress: Math.floor((totalScore / nextLevelInfo.nextLevel.pointsRequired) * 100)
        };
      }
      
      // Return enhanced link data with complete player info
      res.json({
        success: true,
        link: {
          ...link,
          // Player info
          playerLevel: playerLevel.title,
          playerLevelId: playerLevel.id,
          playerScore: totalScore,
          
          // Progression info
          progression: progressionInfo,
          
          // Difficulty guidance
          optimalDifficulty: optimalDifficulty,
          
          // Level config for client-side calculations
          levelConfig: {
            version: levelConfig.version,
            skillLevels: levelConfig.skillLevels
          }
        }
      });
      
    } catch (error) {
      console.error('❌ CONTRIB: Error validating contribution token:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to validate contribution link' 
      });
    }
  });

  // Submit phrase via contribution link
  router.post('/api/contribution/:token/submit', async (req, res) => {
    try {
      const { token } = req.params;
      const { phrase, theme, clue, language = 'en', contributorName } = req.body;
      
      console.log(`📝 CONTRIB: Submitting phrase for token: ${token}`);
      
      // Validate token
      const validation = await linkGenerator.validateToken(token);
      if (!validation.valid) {
        return res.status(400).json({ 
          success: false, 
          error: validation.reason 
        });
      }

      // Validate phrase
      if (!phrase || typeof phrase !== 'string') {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase is required' 
        });
      }

      const trimmedPhrase = phrase.trim();
      if (trimmedPhrase.length < 3) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must be at least 3 characters long' 
        });
      }

      if (trimmedPhrase.length > 200) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must be less than 200 characters' 
        });
      }

      // Validate clue (required)
      if (!clue || typeof clue !== 'string' || clue.trim().length === 0) {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue is required' 
        });
      }

      if (clue.trim().length > 500) {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue must be less than 500 characters' 
        });
      }

      // Validate language
      if (!['en', 'sv'].includes(language)) {
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid language' 
        });
      }

      // Create phrase in database
      const DatabasePhrase = require('../shared/database/models/DatabasePhrase');
      const phraseData = {
        content: trimmedPhrase,
        hint: clue.trim(),
        theme: theme && theme.trim() ? theme.trim() : null,
        language: language,
        createdByPlayerId: null, // External contribution
        targetPlayerId: validation.link.requestingPlayerId,
        source: 'external',
        contributionLinkId: validation.link.id
      };

      const createdPhrase = await DatabasePhrase.create(phraseData);
      
      if (!createdPhrase) {
        return res.status(500).json({ 
          success: false, 
          error: 'Failed to create phrase' 
        });
      }

      // Record the contribution
      const contributorInfo = {
        name: contributorName || null,
        ip: req.ip || req.connection.remoteAddress
      };

      const recordResult = await linkGenerator.recordContribution(token, contributorInfo);

      console.log(`✅ CONTRIB: Phrase created successfully for ${validation.link.requestingPlayerName}`);

      res.status(201).json({
        success: true,
        phrase: {
          id: createdPhrase.id,
          content: createdPhrase.content,
          hint: createdPhrase.hint,
          theme: createdPhrase.theme,
          language: createdPhrase.language
        },
        remainingUses: recordResult.remainingUses,
        message: 'Phrase submitted successfully!'
      });

    } catch (error) {
      console.error('❌ CONTRIB: Error submitting contribution:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to submit phrase' 
      });
    }
  });

  return router;
};