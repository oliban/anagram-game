class MonitoringDashboard {
    constructor() {
        this.socket = null;
        this.isAutoScrolling = true;
        this.activities = [];
        this.stats = {
            onlinePlayers: 0,
            activePhrases: 0,
            phrasesToday: 0,
            completionRate: 0
        };
        this.filters = {
            player: true,
            phrase: true,
            game: true,
            system: true,
            timeRange: '24h'
        };
        
        this.init();
    }

    async init() {
        console.log('🚀 Initializing monitoring dashboard...');
        this.setupEventListeners();
        this.showConnectionStatus('connecting');
        
        // Check if Socket.IO is available
        if (typeof io === 'undefined') {
            console.error('❌ Socket.IO library not loaded!');
            this.showConnectionStatus('disconnected');
            return;
        }
        console.log('✅ Socket.IO library loaded');
        
        try {
            console.log('🔌 Attempting WebSocket connection...');
            await this.connectWebSocket();
            console.log('📊 Loading initial data...');
            await this.loadInitialData();
            console.log('✅ Dashboard initialized successfully');
            this.showConnectionStatus('connected');
        } catch (error) {
            console.error('❌ Failed to initialize dashboard:', error);
            this.showConnectionStatus('disconnected');
        }
    }

    setupEventListeners() {
        document.getElementById('clear-feed').addEventListener('click', () => {
            this.clearActivityFeed();
        });

        document.getElementById('toggle-auto-scroll').addEventListener('click', () => {
            this.toggleAutoScroll();
        });

        ['player', 'phrase', 'game', 'system'].forEach(type => {
            document.getElementById(`filter-${type}`).addEventListener('change', (e) => {
                this.filters[type] = e.target.checked;
                this.applyFilters();
            });
        });

        document.getElementById('time-range').addEventListener('change', (e) => {
            this.filters.timeRange = e.target.value;
            this.applyFilters();
        });
    }

    async connectWebSocket() {
        // Use HTTP polling instead of WebSocket for this service
        console.log('🔌 Using HTTP polling instead of WebSocket...');
        this.startPolling();
        return Promise.resolve();
    }

    async loadInitialData() {
        try {
            console.log('📊 Loading initial data...');
            const statsResponse = await apiClient.get('/monitoring/stats');
            console.log('📊 Received stats:', statsResponse);
            this.updateStats(statsResponse);
            
            // Update the player and phrase lists with real data
            if (statsResponse.activePlayers) {
                this.updatePlayersList(statsResponse.activePlayers);
            }
            if (statsResponse.recentPhrases) {
                this.updatePhrasesList(statsResponse.recentPhrases);
            }
            // Add recent activities to the feed
            if (statsResponse.recentActivities && statsResponse.recentActivities.length > 0) {
                // Clear loading message
                const feed = document.getElementById('activity-feed');
                feed.innerHTML = '';
                
                // Add activities
                statsResponse.recentActivities.forEach(activity => {
                    this.addActivity(activity);
                });
            }
        } catch (error) {
            console.error('Failed to load initial data:', error);
        }
    }

    startPolling() {
        // Poll for updates every 10 seconds
        this.pollingInterval = setInterval(async () => {
            try {
                await this.loadInitialData();
            } catch (error) {
                console.error('Polling error:', error);
            }
        }, 10000);
        
        // Load initial data immediately
        this.loadInitialData();
    }

    addActivity(activity) {
        const timestamp = new Date(activity.timestamp || Date.now());
        const activityItem = {
            ...activity,
            timestamp,
            id: Date.now() + Math.random()
        };

        this.activities.unshift(activityItem);
        
        if (this.activities.length > 1000) {
            this.activities = this.activities.slice(0, 1000);
        }

        this.renderActivity(activityItem, true);
    }

    renderActivity(activity, isNew = false) {
        console.log('🎨 renderActivity called with:', activity, 'isNew:', isNew);
        
        const feed = document.getElementById('activity-feed');
        console.log('📦 Activity feed element:', feed);
        
        if (!feed) {
            console.error('❌ Activity feed element not found!');
            return;
        }
        
        const existingLoading = feed.querySelector('.loading');
        if (existingLoading) {
            console.log('🗑️ Removing loading indicator');
            existingLoading.remove();
        }

        const activityElement = document.createElement('div');
        activityElement.className = `activity-item ${isNew ? 'new-item' : ''}`;
        activityElement.dataset.type = activity.type;
        
        // Fix timestamp handling - convert string to Date first
        const timestamp = activity.timestamp instanceof Date ? activity.timestamp : new Date(activity.timestamp);
        activityElement.dataset.timestamp = timestamp.getTime();
        console.log('⏰ Timestamp processed:', timestamp);

        const time = timestamp.toLocaleTimeString('en-US', {
            hour12: false,
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });

        activityElement.innerHTML = `
            <div class="activity-timestamp">${time}</div>
            <div class="activity-type ${activity.type}">${activity.type}</div>
            <div class="activity-message">
                ${activity.message}
                ${activity.details ? `<div class="activity-details">${JSON.stringify(activity.details)}</div>` : ''}
            </div>
        `;

        console.log('🏗️ Created activity element:', activityElement);

        if (isNew) {
            console.log('➕ Prepending to feed');
            feed.prepend(activityElement);
        } else {
            console.log('➕ Appending to feed');
            feed.appendChild(activityElement);
        }

        console.log('📊 Feed children count after add:', feed.children.length);

        if (this.isAutoScrolling && isNew) {
            console.log('📜 Auto-scrolling to new item');
            activityElement.scrollIntoView({ behavior: 'smooth' });
        }

        console.log('🔍 Applying filters...');
        this.applyFilters();
        console.log('✅ renderActivity completed');
    }

    updateStats(stats) {
        console.log('🔄 updateStats called with:', stats);
        this.stats = { ...this.stats, ...stats };
        
        console.log('📊 Updating basic stats...');
        document.getElementById('online-players').textContent = this.stats.onlinePlayers;
        document.getElementById('active-phrases').textContent = this.stats.activePhrases;
        document.getElementById('phrases-today').textContent = this.stats.phrasesToday;
        document.getElementById('completion-rate').textContent = `${this.stats.completionRate}%`;
        
        // Update inventory if present
        if (stats.phraseInventory) {
            console.log('📦 Updating inventory display with:', stats.phraseInventory);
            this.updateInventoryDisplay(stats.phraseInventory);
        }
        
        // Update language inventory if present
        if (stats.languageInventory) {
            console.log('🌐 Updating language inventory with:', stats.languageInventory);
            this.updateLanguageInventory(stats.languageInventory);
        }
        
        // Update depletion if present
        if (stats.playersNearingDepletion) {
            console.log('⚠️ Updating depletion list with:', stats.playersNearingDepletion);
            this.updateDepletionList(stats.playersNearingDepletion);
        }
        
        console.log('✅ updateStats completed');
    }

    updatePlayersList(players) {
        const playersList = document.getElementById('players-list');
        
        if (!players || players.length === 0) {
            playersList.innerHTML = '<div class="no-data">No active players</div>';
            return;
        }

        playersList.innerHTML = players.map(player => `
            <div class="player-item ${player.status}">
                <div class="player-name">${player.name}</div>
                <div class="player-info">
                    <span class="player-score">${player.score} pts</span>
                    <span class="player-status">${player.status}</span>
                </div>
            </div>
        `).join('');
    }

    updatePhrasesList(phrases) {
        const phrasesList = document.getElementById('phrases-list');
        
        if (!phrases || phrases.length === 0) {
            phrasesList.innerHTML = '<div class="no-data">No recent phrases</div>';
            return;
        }

        phrasesList.innerHTML = phrases.map(phrase => `
            <div class="phrase-item">
                <div class="phrase-content">"${phrase.content}"</div>
                <div class="phrase-info">
                    <span class="phrase-difficulty ${phrase.difficulty}">${phrase.difficulty}</span>
                    <span class="phrase-time">${this.formatTime(phrase.createdAt)}</span>
                </div>
            </div>
        `).join('');
    }
    
    formatTime(timestamp) {
        const date = new Date(timestamp);
        return date.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    updateInventoryDisplay(inventory) {
        // Update inventory numbers
        document.getElementById('phrases-very-easy').textContent = inventory.veryEasy || 0;
        document.getElementById('phrases-easy').textContent = inventory.easy || 0;
        document.getElementById('phrases-medium').textContent = inventory.medium || 0;
        document.getElementById('phrases-hard').textContent = inventory.hard || 0;
        document.getElementById('phrases-very-hard').textContent = inventory.veryHard || 0;

        // Update status classes based on counts
        const updateInventoryStatus = (elementId, count) => {
            const card = document.querySelector(`#${elementId}`).closest('.inventory-card');
            // Remove existing status classes
            card.classList.remove('critical', 'low', 'good');
            
            // Add appropriate status class
            if (count === 0) {
                card.classList.add('critical');
            } else if (count < 10) {
                card.classList.add('low');
            } else {
                card.classList.add('good');
            }
        };

        updateInventoryStatus('phrases-very-easy', inventory.veryEasy || 0);
        updateInventoryStatus('phrases-easy', inventory.easy || 0);
        updateInventoryStatus('phrases-medium', inventory.medium || 0);
        updateInventoryStatus('phrases-hard', inventory.hard || 0);
        updateInventoryStatus('phrases-very-hard', inventory.veryHard || 0);
    }
    
    updateLanguageInventory(languageInventory) {
        // Update language inventory for each language
        ['en', 'sv'].forEach(lang => {
            const data = languageInventory[lang] || { veryEasy: 0, easy: 0, medium: 0, hard: 0, veryHard: 0, total: 0 };
            
            // Update total
            document.getElementById(`lang-${lang}-total`).textContent = data.total;
            
            // Update breakdown
            document.getElementById(`lang-${lang}-veryEasy`).textContent = data.veryEasy;
            document.getElementById(`lang-${lang}-easy`).textContent = data.easy;
            document.getElementById(`lang-${lang}-medium`).textContent = data.medium;
            document.getElementById(`lang-${lang}-hard`).textContent = data.hard;
            document.getElementById(`lang-${lang}-veryHard`).textContent = data.veryHard;
            
            // Update card status based on total
            const card = document.getElementById(`lang-${lang}`);
            card.classList.remove('critical', 'low', 'good');
            
            if (data.total === 0) {
                card.classList.add('critical');
            } else if (data.total < 50) {
                card.classList.add('low');
            } else {
                card.classList.add('good');
            }
        });
    }

    updateDepletionList(playersNearingDepletion) {
        const depletionList = document.getElementById('depletion-list');
        
        if (playersNearingDepletion.length === 0) {
            depletionList.innerHTML = '<div class="no-data">No players nearing phrase depletion</div>';
            return;
        }

        depletionList.innerHTML = playersNearingDepletion.map(player => {
            const timeSinceLastSeen = this.formatTimeSince(new Date(player.lastSeen));
            
            return `
                <div class="depletion-item">
                    <div class="depletion-player">
                        <div class="depletion-name">${player.name}</div>
                        <div class="depletion-level">Level ${player.playerLevel} • Last seen ${timeSinceLastSeen}</div>
                    </div>
                    <div class="depletion-stats">
                        <span class="depletion-count ${player.depletionStatus}">
                            ${player.availablePhrases} left
                        </span>
                        <span class="depletion-status ${player.depletionStatus}">
                            ${player.depletionStatus}
                        </span>
                    </div>
                </div>
            `;
        }).join('');
    }

    formatTimeSince(date) {
        const now = new Date();
        const diffInSeconds = Math.floor((now - date) / 1000);
        
        if (diffInSeconds < 60) return 'just now';
        if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
        if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
        return `${Math.floor(diffInSeconds / 86400)}d ago`;
    }

    applyFilters() {
        console.log('🔍 applyFilters called, current filters:', this.filters);
        
        const feed = document.getElementById('activity-feed');
        const items = feed.querySelectorAll('.activity-item');
        const now = Date.now();
        
        console.log('📋 Found activity items:', items.length);
        
        let cutoffTime = 0;
        switch (this.filters.timeRange) {
            case '1h':
                cutoffTime = now - (60 * 60 * 1000);
                break;
            case '24h':
                cutoffTime = now - (24 * 60 * 60 * 1000);
                break;
            case '7d':
                cutoffTime = now - (7 * 24 * 60 * 60 * 1000);
                break;
            default:
                cutoffTime = 0;
        }
        
        console.log('⏰ Filter cutoff time:', new Date(cutoffTime));

        items.forEach((item, index) => {
            const type = item.dataset.type;
            const timestamp = parseInt(item.dataset.timestamp);
            
            const typeVisible = this.filters[type] !== false;
            const timeVisible = timestamp >= cutoffTime;
            
            console.log(`📄 Item ${index}: type="${type}", timestamp=${timestamp} (${new Date(timestamp)}), typeVisible=${typeVisible}, timeVisible=${timeVisible}`);
            
            const shouldShow = typeVisible && timeVisible;
            item.style.display = shouldShow ? 'flex' : 'none';
            
            console.log(`👁️ Item ${index} display set to: ${item.style.display}`);
        });
        
        console.log('✅ applyFilters completed');
    }

    clearActivityFeed() {
        const feed = document.getElementById('activity-feed');
        feed.innerHTML = '<div class="no-data">Activity feed cleared</div>';
        this.activities = [];
    }

    toggleAutoScroll() {
        this.isAutoScrolling = !this.isAutoScrolling;
        const button = document.getElementById('toggle-auto-scroll');
        const text = document.getElementById('auto-scroll-text');
        text.textContent = `Auto-scroll: ${this.isAutoScrolling ? 'ON' : 'OFF'}`;
        button.className = `btn ${this.isAutoScrolling ? 'btn-success' : 'btn-secondary'}`;
    }

    showConnectionStatus(status) {
        let existingStatus = document.querySelector('.connection-status');
        if (!existingStatus) {
            existingStatus = document.createElement('div');
            existingStatus.className = 'connection-status';
            document.body.appendChild(existingStatus);
        }

        existingStatus.className = `connection-status ${status}`;
        
        switch (status) {
            case 'connected':
                existingStatus.textContent = '🟢 Connected';
                break;
            case 'connecting':
                existingStatus.textContent = '🟡 Connecting...';
                break;
            case 'disconnected':
                existingStatus.textContent = '🔴 Disconnected';
                break;
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.monitoringDashboard = new MonitoringDashboard();
});