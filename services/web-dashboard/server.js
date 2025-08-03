const express = require('express');
const path = require('path');
const { testConnection, pool } = require('./shared/database/connection');
const levelConfig = require('./shared/config/level-config.json');

const app = express();

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

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
// Also serve static files from /web/ path for compatibility
app.use('/web', express.static(path.join(__dirname, 'public')));

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'web-dashboard',
    timestamp: new Date().toISOString() 
  });
});

// Monitoring stats endpoint
app.get('/api/monitoring/stats', async (req, res) => {
    try {
        const stats = await getMonitoringStats();
        res.json(stats);
    } catch (error) {
        console.error('Error fetching monitoring stats:', error);
        res.status(500).json({ error: 'Failed to fetch monitoring stats' });
    }
});

// Get contribution link details with REAL player data
app.get('/api/contribution/:token', async (req, res) => {
  try {
    const { token } = req.params;
    console.log(`🔍 API: Looking up contribution token: ${token}`);
    
    // Get link data from contribution_links table
    const linkQuery = `
      SELECT 
        cl.id,
        cl.token,
        cl.requesting_player_id,
        cl.expires_at,
        cl.max_uses,
        cl.current_uses,
        cl.is_active,
        p.name as requesting_player_name
      FROM contribution_links cl
      JOIN players p ON cl.requesting_player_id = p.id
      WHERE cl.token = $1
    `;
    
    const linkResult = await pool.query(linkQuery, [token]);
    
    if (linkResult.rows.length === 0) {
      console.log(`❌ API: Token not found: ${token}`);
      return res.status(400).json({ 
        success: false, 
        error: 'Invalid contribution token' 
      });
    }

    const link = linkResult.rows[0];
    console.log(`✅ API: Found link for player: ${link.requesting_player_name}`);
    
    // Check if link is valid
    if (!link.is_active) {
      return res.status(400).json({ 
        success: false, 
        error: 'Link has been deactivated' 
      });
    }

    if (new Date() > new Date(link.expires_at)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Link has expired' 
      });
    }

    if (link.current_uses >= link.max_uses) {
      return res.status(400).json({ 
        success: false, 
        error: 'Link usage limit reached' 
      });
    }

    // Get player score data from database
    const scoreQuery = `
      SELECT COALESCE(SUM(cp.score), 0) as total_score
      FROM completed_phrases cp
      WHERE cp.player_id = $1
    `;
    const scoreResult = await pool.query(scoreQuery, [link.requesting_player_id]);
    const totalScore = scoreResult.rows[0]?.total_score || 0;
    
    console.log(`📊 API: Player ${link.requesting_player_name} has ${totalScore} points`);
    
    // Calculate player level
    const playerLevel = getPlayerLevel(totalScore);
    console.log(`🏆 API: Player level: ${playerLevel.title} (Level ${playerLevel.id})`);
    
    // Return enhanced link data with real player info
    res.json({
      success: true,
      link: {
        id: link.id,
        token: link.token,
        requestingPlayerId: link.requesting_player_id,
        requestingPlayerName: link.requesting_player_name,
        expiresAt: link.expires_at,
        maxUses: link.max_uses,
        currentUses: link.current_uses,
        remainingUses: link.max_uses - link.current_uses,
        playerLevel: playerLevel.title,
        playerScore: totalScore,
        legendThreshold: 2000 // Points needed for legendary status
      }
    });
    
  } catch (error) {
    console.error('❌ API: Error validating contribution token:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to validate contribution link' 
    });
  }
});

// Serve dashboard pages
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/contribute', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'contribute', 'index.html'));
});

// Handle contribution links with tokens
app.get('/contribute/:token', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'contribute', 'index.html'));
});

app.get('/monitoring', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'monitoring', 'index.html'));
});

// Helper function to get monitoring stats
async function getMonitoringStats() {
    try {
        const [playersResult, phrasesResult, todayPhrasesResult] = await Promise.all([
            pool.query('SELECT COUNT(*) as count FROM players WHERE is_active = true AND last_seen > NOW() - INTERVAL \'5 minutes\''),
            pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > NOW() - INTERVAL \'24 hours\''),
            pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > CURRENT_DATE')
        ]);

        const completedResult = await pool.query(`
            SELECT 
                COUNT(*) as completed,
                COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM phrases WHERE created_at > NOW() - INTERVAL '24 hours'), 0) as completion_rate
            FROM completed_phrases cp
            JOIN phrases p ON cp.phrase_id = p.id
            WHERE cp.completed_at > NOW() - INTERVAL '24 hours'
        `);

        // Get phrase inventory by difficulty
        const inventoryResult = await getPhraseInventoryByDifficulty();
        
        // Get players nearing phrase depletion
        const playersNearingDepletion = await getPlayersNearingPhraseDepletion();

        return {
            onlinePlayers: parseInt(playersResult.rows[0].count),
            activePhrases: parseInt(phrasesResult.rows[0].count),
            phrasesToday: parseInt(todayPhrasesResult.rows[0].count),
            completionRate: Math.round(parseFloat(completedResult.rows[0].completion_rate || 0)),
            phraseInventory: inventoryResult,
            playersNearingDepletion: playersNearingDepletion
        };
    } catch (error) {
        console.error('Error calculating monitoring stats:', error);
        return {
            onlinePlayers: 0,
            activePhrases: 0,
            phrasesToday: 0,
            completionRate: 0,
            phraseInventory: {
                veryEasy: 0,
                easy: 0,
                medium: 0,
                hard: 0,
                veryHard: 0
            },
            playersNearingDepletion: []
        };
    }
}

// Helper function to get phrase inventory by difficulty ranges
async function getPhraseInventoryByDifficulty() {
    try {
        const inventoryQuery = `
            WITH phrase_difficulty AS (
                SELECT 
                    CASE 
                        WHEN difficulty_level <= 20 THEN 'veryEasy'
                        WHEN difficulty_level <= 40 THEN 'easy'
                        WHEN difficulty_level <= 60 THEN 'medium'
                        WHEN difficulty_level <= 80 THEN 'hard'
                        ELSE 'veryHard'
                    END as difficulty_range,
                    id
                FROM phrases 
                WHERE is_global = true 
                    AND is_approved = true
                    AND NOT EXISTS (
                        SELECT 1 FROM completed_phrases cp 
                        WHERE cp.phrase_id = phrases.id
                    )
            )
            SELECT 
                difficulty_range,
                COUNT(*) as phrase_count
            FROM phrase_difficulty
            GROUP BY difficulty_range
            ORDER BY 
                CASE difficulty_range
                    WHEN 'veryEasy' THEN 1
                    WHEN 'easy' THEN 2
                    WHEN 'medium' THEN 3
                    WHEN 'hard' THEN 4
                    WHEN 'veryHard' THEN 5
                END
        `;

        const result = await pool.query(inventoryQuery);
        
        // Initialize with zeros
        const inventory = {
            veryEasy: 0,
            easy: 0,
            medium: 0,
            hard: 0,
            veryHard: 0
        };

        // Fill in actual counts
        result.rows.forEach(row => {
            inventory[row.difficulty_range] = parseInt(row.phrase_count);
        });

        console.log('📊 INVENTORY: Phrase counts by difficulty:', inventory);
        return inventory;

    } catch (error) {
        console.error('❌ INVENTORY: Error getting phrase inventory:', error);
        return {
            veryEasy: 0,
            easy: 0,
            medium: 0,
            hard: 0,
            veryHard: 0
        };
    }
}

// Helper function to get players nearing phrase depletion
async function getPlayersNearingPhraseDepletion() {
    try {
        const depletionQuery = `
            WITH player_stats as (
                SELECT 
                    p.id,
                    p.name,
                    p.is_active,
                    p.last_seen,
                    COUNT(cp.phrase_id) as phrases_completed,
                    -- Calculate available phrases for player's level range
                    (
                        SELECT COUNT(*) 
                        FROM phrases ph
                        WHERE ph.is_global = true 
                            AND ph.is_approved = true
                            AND ph.difficulty_level <= COALESCE(p.level, 1) * 50  -- Assuming level * 50 = max difficulty
                            AND NOT EXISTS (
                                SELECT 1 FROM completed_phrases cp2 
                                WHERE cp2.phrase_id = ph.id AND cp2.player_id = p.id
                            )
                    ) as available_phrases,
                    -- Player's current level (default to 1 if null)
                    COALESCE(p.level, 1) as player_level
                FROM players p
                LEFT JOIN completed_phrases cp ON p.id = cp.player_id
                WHERE p.is_active = true 
                    AND p.last_seen > NOW() - INTERVAL '7 days'  -- Active in last 7 days
                GROUP BY p.id, p.name, p.is_active, p.last_seen, p.level
            )
            SELECT 
                id,
                name,
                phrases_completed,
                available_phrases,
                player_level,
                last_seen,
                CASE 
                    WHEN available_phrases = 0 THEN 'critical'
                    WHEN available_phrases < 5 THEN 'low'
                    WHEN available_phrases < 15 THEN 'medium'
                    ELSE 'good'
                END as depletion_status
            FROM player_stats
            WHERE available_phrases < 20  -- Only show players with less than 20 available phrases
            ORDER BY available_phrases ASC, phrases_completed DESC
            LIMIT 20
        `;

        const result = await pool.query(depletionQuery);
        
        const playersNearingDepletion = result.rows.map(row => ({
            id: row.id,
            name: row.name,
            phrasesCompleted: parseInt(row.phrases_completed),
            availablePhrases: parseInt(row.available_phrases),
            playerLevel: parseInt(row.player_level),
            lastSeen: row.last_seen,
            depletionStatus: row.depletion_status
        }));

        console.log(`📊 DEPLETION: Found ${playersNearingDepletion.length} players nearing phrase depletion`);
        return playersNearingDepletion;

    } catch (error) {
        console.error('❌ DEPLETION: Error getting players nearing depletion:', error);
        return [];
    }
}

const PORT = 3001;

// Initialize database and start server
async function startServer() {
  try {
    await testConnection();
    console.log('✅ Database connected successfully');
    
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`📊 Web Dashboard running on port ${PORT}`);
      console.log(`🌐 Dashboard: http://0.0.0.0:${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start web dashboard:', error);
    process.exit(1);
  }
}

startServer();