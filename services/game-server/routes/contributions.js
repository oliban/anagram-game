const express = require('express');
const path = require('path');
const router = express.Router();
console.log('🔍 CONTRIB: Loading ContributionLinkGenerator...');
const ContributionLinkGenerator = require('../contribution-link-generator');
console.log('✅ CONTRIB: ContributionLinkGenerator loaded successfully');

// Contribution routes factory - integrated into game-server
module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePlayer, 
    DatabasePhrase, 
    ScoringSystem,
    broadcastActivity,
    io,
    query,
    pool,
    configService
  } = dependencies;

  const linkGenerator = new ContributionLinkGenerator();

  // Simple helper function to get basic player info
  async function getBasicPlayerInfo(playerId) {
    try {
      console.log('🔍 CONTRIB: Getting basic player stats...');
      const playerStats = await DatabasePlayer.getPlayerStats(playerId);
      console.log('🔍 CONTRIB: Player stats retrieved:', playerStats);
      
      if (!playerStats) {
        console.error('❌ CONTRIB: Player stats returned null');
        return null;
      }
      
      const totalScore = parseInt(playerStats.total_score) || 0;
      console.log('🔍 CONTRIB: Total score:', totalScore);
      
      // Simple level determination based on score
      let playerLevel;
      if (totalScore === 0) {
        playerLevel = { id: 1, title: 'Beginner' };
      } else if (totalScore < 100) {
        playerLevel = { id: 2, title: 'Novice' };
      } else if (totalScore < 500) {
        playerLevel = { id: 3, title: 'Intermediate' };
      } else {
        playerLevel = { id: 4, title: 'Advanced' };
      }
      
      return {
        playerLevel,
        totalScore,
        progressionInfo: {
          nextLevelPoints: totalScore + 100,
          pointsToNext: 100 - (totalScore % 100),
          progressPercent: (totalScore % 100)
        },
        optimalDifficulty: {
          min: Math.max(10, totalScore / 10),
          max: Math.max(30, totalScore / 5)
        }
      };
    } catch (error) {
      console.error('❌ CONTRIB: Error getting player info:', error);
      return null;
    }
  }

  // Legacy status endpoint for backward compatibility (MUST come before /:token routes)
  router.get('/api/contribution/status', async (req, res) => {
    console.log('🔍 CONTRIB STATUS: Route accessed successfully');
    res.json({
      status: 'healthy',
      service: 'game-server-contributions',
      timestamp: new Date().toISOString(),
      integration: 'Contribution system integrated into game-server'
    });
  });

  // Serve contribution page
  router.get('/contribute/:token', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'public', 'contribute', 'index.html'));
  });

  // Get contribution link details with REAL player data (for the web page)
  router.get('/api/contribution/:token', async (req, res) => {
    try {
      const { token } = req.params;
      console.log(`🔍 CONTRIB: Looking up contribution token: ${token}`);
      
      const validation = await linkGenerator.validateToken(token);
      
      if (!validation) {
        console.log(`❌ CONTRIB: Token validation failed: invalid, expired, or exhausted`);
        
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid, expired, or exhausted contribution link' 
        });
      }

      // validation now contains the token data directly
      const link = validation;
      console.log(`✅ CONTRIB: Found link for player: ${link.requestingPlayerName}`);
      
      // Get basic player info with fallbacks
      console.log('🔍 CONTRIB: About to get basic player info');
      const playerInfo = await getBasicPlayerInfo(link.requestingPlayerId);
      
      if (!playerInfo) {
        console.error('❌ CONTRIB: Failed to get basic player info, using defaults');
        // Use absolute defaults if even basic info fails
        res.json({
          success: true,
          validation: { valid: true, reason: null },
          link: {
            ...link,
            playerLevel: 'Beginner',
            playerLevelId: 1,
            playerScore: '0',
            progression: { nextLevelPoints: 100, pointsToNext: 100, progressPercent: 0 },
            optimalDifficulty: { min: 10, max: 30 },
            levelConfig: { version: '1.0', skillLevels: [] }
          }
        });
        return;
      }
      
      console.log('✅ CONTRIB: Using player info - Level:', playerInfo.playerLevel.title, 'Score:', playerInfo.totalScore);
      
      // Return enhanced link data with actual player info
      res.json({
        success: true,
        validation: {
          valid: true,
          reason: null
        },
        link: {
          ...link,
          // Player info
          playerLevel: playerInfo.playerLevel.title,
          playerLevelId: playerInfo.playerLevel.id,
          playerScore: playerInfo.totalScore.toString(),
          
          // Progression info
          progression: playerInfo.progressionInfo,
          
          // Difficulty guidance
          optimalDifficulty: playerInfo.optimalDifficulty,
          
          // Simple level config
          levelConfig: {
            version: '1.0',
            skillLevels: []
          }
        }
      });
      console.log('✅ CONTRIB: Response sent successfully');
      
    } catch (error) {
      console.error('❌ CONTRIB: Error getting contribution details:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to get contribution details' 
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
      if (!validation) {
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid, expired, or exhausted contribution link' 
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

      if (trimmedPhrase.length > 40) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must be 40 characters or less' 
        });
      }

      // Validate clue
      if (!clue || typeof clue !== 'string') {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue is required' 
        });
      }

      const trimmedClue = clue.trim();
      if (trimmedClue.length < 3) {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue must be at least 3 characters long' 
        });
      }

      if (trimmedClue.length > 32) {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue must be 32 characters or less' 
        });
      }

      // Validate contributor name if provided
      if (contributorName && contributorName.trim().length > 10) {
        return res.status(400).json({ 
          success: false, 
          error: 'Contributor name must be 10 characters or less' 
        });
      }

      // Create phrase in database - target the requesting player
      try {
        console.log(`💾 CONTRIB: Creating targeted phrase for player: ${validation.requestingPlayerName}`);
        
        // Create the phrase entry using enhanced method (handles difficulty calculation)
        const result = await DatabasePhrase.createEnhancedPhrase({
          content: trimmedPhrase,
          hint: trimmedClue,
          senderId: null, // External contribution (no specific sender)
          targetIds: [validation.requestingPlayerId], // Target specific player
          isGlobal: false, // Not global, targeted to specific player
          phraseType: 'custom',
          language: language || 'en',
          theme: theme?.trim() || null,
          contributorName: contributorName?.trim() || 'Anonymous'
        });
        
        const newPhrase = result.phrase;

        console.log(`✅ CONTRIB: Created phrase with ID: ${newPhrase.id}`);
        
        // Increment link usage
        await linkGenerator.incrementUsage(token);
        console.log(`📊 CONTRIB: Incremented link usage for token: ${token}`);
        
        // Notify the target player via WebSocket (direct integration!)
        try {
          const player = await DatabasePlayer.getPlayerById(validation.requestingPlayerId);
          
          if (player && player.socketId && io) {
            console.log(`🔔 CONTRIB: Notifying player ${validation.requestingPlayerName} via WebSocket (${player.socketId})`);
            
            // Emit to specific player socket using same format as regular phrases
            const phraseData = newPhrase.getPublicInfo();
            // Ensure targetId is set for iOS client priority queue
            phraseData.targetId = validation.requestingPlayerId;
            
            // Override senderName in phraseData to ensure correct contributor name
            phraseData.senderName = newPhrase.contributorName || 'Anonymous';
            
            const webSocketPayload = {
              phrase: phraseData,
              senderName: newPhrase.contributorName || 'Anonymous',
              timestamp: new Date().toISOString()
            };
            
            
            // Emit the WebSocket event
            io.to(player.socketId).emit('new-phrase', webSocketPayload);

            // Also broadcast activity to monitoring
            if (broadcastActivity) {
              broadcastActivity('contribution', `Phrase "${trimmedPhrase}" contributed to ${validation.requestingPlayerName}`, {
                playerId: validation.requestingPlayerId,
                phraseId: newPhrase.id,
                contributor: contributorName || 'Anonymous'
              });
            }
            
            console.log(`✅ CONTRIB: Successfully notified player via WebSocket`);
          } else {
            console.log(`⚠️ CONTRIB: Player ${validation.requestingPlayerName} not currently connected`);
          }
        } catch (notifyError) {
          console.error('❌ CONTRIB: Error sending WebSocket notification:', notifyError.message);
          // Don't fail the whole request just because notification failed
        }

        res.json({
          success: true,
          message: 'Phrase submitted successfully',
          phrase: {
            id: newPhrase.id,
            content: newPhrase.content,
            hint: newPhrase.hint,
            theme: newPhrase.theme,
            difficulty: newPhrase.difficulty_level,
            contributorName: newPhrase.contributor_name
          },
          targetPlayer: {
            name: validation.requestingPlayerName,
            id: validation.requestingPlayerId
          }
        });

      } catch (dbError) {
        console.error('❌ CONTRIB: Error creating phrase:', dbError);
        return res.status(500).json({ 
          success: false, 
          error: 'Failed to save phrase to database' 
        });
      }
      
    } catch (error) {
      console.error('❌ CONTRIB: Error submitting phrase:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to submit phrase' 
      });
    }
  });

  // Create contribution link (moved from separate route)
  router.post('/api/contribution/request', async (req, res) => {
    try {
      const { playerId } = req.body;
      
      if (!playerId) {
        return res.status(400).json({ 
          success: false, 
          error: 'Player ID is required' 
        });
      }

      // Verify player exists
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({ 
          success: false, 
          error: 'Player not found' 
        });
      }

      // Create contribution link
      const link = await linkGenerator.createContributionLink(playerId);
      
      console.log(`🔗 CONTRIB: Created link for player ${player.name}: ${link.shareableUrl}`);
      
      res.json({
        success: true,
        link: link
      });
      
    } catch (error) {
      console.error('❌ CONTRIB: Error creating contribution link:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to create contribution link' 
      });
    }
  });


  return router;
};