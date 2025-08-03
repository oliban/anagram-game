const express = require('express');
const path = require('path');
const router = express.Router();

// Player routes - registration, online status, legends, and scores

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePlayer, 
    broadcastActivity, 
    io, 
    query, 
    pool,
    ScoringSystem,
    getMonitoringStats 
  } = dependencies;

  // Player registration
  router.post('/api/players/register', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for player registration'
        });
      }
      
      const { name, deviceId, socketId } = req.body;
      
      // Development debug logging for device-user association
      if (process.env.NODE_ENV === 'development') {
        console.log(`🔍 REGISTRATION: name='${name}', deviceId='${deviceId}', socketId='${socketId}'`);
      }
      
      // Validate input
      if (!name || typeof name !== 'string') {
        return res.status(400).json({ 
          error: 'Player name is required and must be a string' 
        });
      }

      if (!deviceId || typeof deviceId !== 'string') {
        return res.status(400).json({ 
          error: 'Device ID is required and must be a string' 
        });
      }

      // Validate socketId if provided
      if (socketId !== null && socketId !== undefined && typeof socketId !== 'string') {
        return res.status(400).json({
          error: 'Socket ID must be a string or null'
        });
      }
      
      // Check if this exact player (name + device_id) already exists
      const existingPlayer = await DatabasePlayer.getPlayerByNameAndDevice(name, deviceId);
      let player;
      let isFirstLogin = false;
      
      if (existingPlayer) {
        // Existing player logging back in with same device
        player = await DatabasePlayer.updatePlayerLogin(existingPlayer.id, socketId || null);
        isFirstLogin = false;
        console.log(`👤 Existing player logged back in: ${player.name} (${player.id})`);
      } else {
        // Check if name is taken by another device
        const nameConflict = await DatabasePlayer.getPlayerByName(name);
        if (nameConflict && nameConflict.deviceId) {
          // Name exists and is tied to a different device - suggest alternatives
          const suggestions = await DatabasePlayer.generateNameSuggestions(name);
          return res.status(409).json({
            error: 'Player name is already taken by another device',
            suggestions: suggestions,
            code: 'NAME_TAKEN_OTHER_DEVICE'
          });
        } else if (nameConflict && nameConflict.deviceId === null) {
          // Name exists but no device associated - claim this player (only if device_id is explicitly NULL)
          const updatedResult = await query(`
            UPDATE players 
            SET device_id = $1, socket_id = $2, is_active = true, last_seen = CURRENT_TIMESTAMP
            WHERE id = $3 AND device_id IS NULL
            RETURNING *
          `, [deviceId, socketId || null, nameConflict.id]);
          
          if (updatedResult.rows.length > 0) {
            player = new DatabasePlayer(updatedResult.rows[0]);
            isFirstLogin = false; // This is an existing player being claimed
            console.log(`👤 Player claimed by device: ${player.name} (${player.id})`);
          } else {
            // Race condition - someone else claimed this player, suggest alternatives
            const suggestions = await DatabasePlayer.generateNameSuggestions(name);
            return res.status(409).json({
              error: 'Player name is already taken by another device',
              suggestions: suggestions,
              code: 'NAME_TAKEN_OTHER_DEVICE'
            });
          }
        } else {
          // New player registration
          player = await DatabasePlayer.createPlayerWithDevice(name, deviceId, socketId || null);
          isFirstLogin = true; // This is a brand new player
          console.log(`👤 New player registered: ${player.name} (${player.id})`);
        }
      }
      console.log(`👤 Player registered: ${player.name} (${player.id})`);
      
      // Broadcast activity to monitoring dashboard
      broadcastActivity('player', `New player registered: ${player.name}`, {
        playerId: player.id,
        name: player.name
      });
      
      // Broadcast new player joined event
      io.emit('player-joined', {
        player: player.getPublicInfo(),
        timestamp: new Date().toISOString()
      });
      
      res.status(201).json({
        success: true,
        player: player.getPublicInfo(),
        isFirstLogin: isFirstLogin,
        message: 'Player registered successfully'
      });
      
    } catch (error) {
      console.error('❌ Registration error:', error);
      
      // Handle specific validation errors as 400 (client errors)
      if (error.message.includes('Player name') || 
          error.message.includes('must be between') ||
          error.message.includes('can only contain') ||
          error.message.includes('is required')) {
        return res.status(400).json({ 
          error: error.message 
        });
      }
      
      // Handle database conflicts with name suggestions
      if (error.message.includes('already taken') || 
          error.message.includes('duplicate') ||
          error.message.includes('unique constraint') ||
          error.message.includes('Player name and device combination already exists') ||
          error.code === '23505') {
        
        try {
          const suggestions = await DatabasePlayer.generateNameSuggestions(name || 'Player');
          return res.status(409).json({
            error: 'Player name is already taken by another device',
            suggestions: suggestions,
            code: 'NAME_TAKEN_OTHER_DEVICE'
          });
        } catch (suggestionError) {
          console.error('❌ Error generating name suggestions:', suggestionError);
          return res.status(409).json({ 
            error: 'Player name is already taken' 
          });
        }
      }
      
      res.status(500).json({ 
        error: error.message || 'Registration failed' 
      });
    }
  });

  // Get online players
  router.get('/api/players/online', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for player data'
        });
      }
      
      const dbPlayers = await DatabasePlayer.getOnlinePlayers();
      const onlinePlayers = dbPlayers.map(player => player.getPublicInfo());
      
      res.json({
        players: onlinePlayers,
        count: onlinePlayers.length,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error('❌ Error getting online players:', error);
      res.status(500).json({ 
        error: 'Failed to get online players' 
      });
    }
  });

  // Get legend players
  router.get('/api/players/legends', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for legend players'
        });
      }

      // Read the minimum skill level from config
      const fs = require('fs').promises;
      const configPath = path.join(__dirname, '../shared/config', 'level-config.json');
      
      let minimumSkillLevel = 2; // Default to wretched (level 2)
      let minimumSkillTitle = 'Wretched';
      let minimumPoints = 230;
      
      try {
        const configData = await fs.readFile(configPath, 'utf8');
        const levelConfig = JSON.parse(configData);
        
        // Find the wretched skill level
        const wretchedLevel = levelConfig.skillLevels?.find(level => level.title === 'wretched');
        if (wretchedLevel) {
          minimumSkillLevel = wretchedLevel.id;
          minimumSkillTitle = wretchedLevel.title.charAt(0).toUpperCase() + wretchedLevel.title.slice(1);
          minimumPoints = wretchedLevel.pointsRequired;
        }
      } catch (configError) {
        console.error('❌ LEGENDS: Error loading level config, using defaults:', configError.message);
      }

      console.log(`👑 LEGENDS: Looking for players with ${minimumPoints}+ points (${minimumSkillTitle} level)`);

      // Query for players with total scores >= minimum points required for wretched level  
      // Use same scoring logic as leaderboard system, get max score per player
      const queryText = `
        SELECT 
          p.id,
          p.name,
          MAX(ps.total_score) as total_score,
          MAX(ps.phrases_completed) as phrases_completed
        FROM players p
        JOIN player_scores ps ON p.id = ps.player_id
        WHERE ps.total_score >= $1
        GROUP BY p.id, p.name
        ORDER BY MAX(ps.total_score) DESC
        LIMIT 50
      `;

      const result = await pool.query(queryText, [minimumPoints]);
      
      // Get each player's rarest emojis (up to 5)
      const legendPlayers = await Promise.all(result.rows.map(async row => {
        const totalScore = parseInt(row.total_score);
        
        // Calculate skill level based on total score using ScoringSystem
        const skillInfo = ScoringSystem.getSkillLevel(totalScore);
        const skillLevel = skillInfo.level;
        const skillTitle = skillInfo.title;
        
        // Get player's 5 rarest emojis
        const rarestEmojisQuery = `
          SELECT 
            ec.emoji_character,
            ec.name,
            ec.rarity_tier,
            ec.drop_rate_percentage,
            pec.is_first_global_discovery
          FROM player_emoji_collections pec
          JOIN emoji_catalog ec ON pec.emoji_id = ec.id
          WHERE pec.player_id = $1
          ORDER BY ec.drop_rate_percentage ASC
          LIMIT 5
        `;
        
        const emojiResult = await pool.query(rarestEmojisQuery, [row.id]);
        
        return {
          id: row.id,
          name: row.name,
          totalScore: totalScore,
          skillLevel: skillLevel,
          skillTitle: skillTitle,
          phrasesCompleted: parseInt(row.phrases_completed),
          rarestEmojis: emojiResult.rows.map(emoji => ({
            emojiCharacter: emoji.emoji_character,
            name: emoji.name,
            rarityTier: emoji.rarity_tier,
            dropRate: parseFloat(emoji.drop_rate_percentage),
            isFirstGlobalDiscovery: emoji.is_first_global_discovery
          }))
        };
      }));

      console.log(`👑 LEGENDS: Found ${legendPlayers.length} legend players`);

      res.json({
        success: true,
        players: legendPlayers,
        minimumSkillLevel: minimumSkillLevel,
        minimumSkillTitle: minimumSkillTitle,
        count: legendPlayers.length,
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('❌ LEGENDS: Error getting legend players:', error);
      res.status(500).json({
        error: 'Failed to get legend players'
      });
    }
  });

  // Get player scores
  router.get('/api/scores/player/:playerId', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for scoring system'
        });
      }

      const { playerId } = req.params;

      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(playerId)) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }

      // Verify player exists
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({
          error: 'Player not found'
        });
      }

      // Get player score summary
      const scores = await ScoringSystem.getPlayerScoreSummary(playerId);
      
      // Get skill level and title based on total score
      const skillInfo = ScoringSystem.getSkillLevel(scores.totalScore);
      
      // Get player's 5 rarest emojis
      const rarestEmojisQuery = `
        SELECT 
          ec.emoji_character,
          ec.name,
          ec.rarity_tier,
          ec.drop_rate_percentage,
          pec.is_first_global_discovery
        FROM player_emoji_collections pec
        JOIN emoji_catalog ec ON pec.emoji_id = ec.id
        WHERE pec.player_id = $1
        ORDER BY ec.drop_rate_percentage ASC
        LIMIT 5
      `;
      
      const emojiResult = await pool.query(rarestEmojisQuery, [playerId]);
      
      res.json({
        success: true,
        playerId,
        playerName: player.name,
        scores: {
          ...scores,
          skillTitle: skillInfo.title,
          skillLevel: skillInfo.level
        },
        rarestEmojis: emojiResult.rows.map(emoji => ({
          emojiCharacter: emoji.emoji_character,
          name: emoji.name,
          rarityTier: emoji.rarity_tier,
          dropRate: parseFloat(emoji.drop_rate_percentage),
          isFirstGlobalDiscovery: emoji.is_first_global_discovery
        })),
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('❌ SCORES: Error getting player scores:', error.message);
      res.status(500).json({
        error: 'Failed to get player scores'
      });
    }
  });

  // Get monitoring stats (moved here from system since it's player-focused)
  router.get('/api/stats', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for stats'
        });
      }
      
      const stats = await getMonitoringStats();
      res.json(stats);
    } catch (error) {
      console.error('❌ Error getting monitoring stats:', error);
      res.status(500).json({ 
        error: 'Failed to get monitoring stats' 
      });
    }
  });

  return router;
};