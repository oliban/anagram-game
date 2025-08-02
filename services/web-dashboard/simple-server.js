const express = require('express');
const path = require('path');
const { pool } = require('./shared/database/connection');
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

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'web-dashboard',
    timestamp: new Date().toISOString() 
  });
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

const PORT = 3001;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`📊 Web Dashboard running on port ${PORT}`);
  console.log(`🌐 Dashboard: http://0.0.0.0:${PORT}`);
});