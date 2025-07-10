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
        return new Promise((resolve, reject) => {
            console.log('🔌 Creating Socket.IO connection to /monitoring namespace...');
            this.socket = io('/monitoring', {
                transports: ['websocket', 'polling'],
                upgrade: true,
                rememberUpgrade: true
            });

            this.socket.on('connect', () => {
                console.log('✅ Connected to monitoring WebSocket, socket ID:', this.socket.id);
                console.log('📡 Requesting stats from server...');
                this.socket.emit('request-stats');
                resolve();
            });

            this.socket.on('disconnect', () => {
                console.log('Disconnected from monitoring WebSocket');
                this.showConnectionStatus('disconnected');
            });

            this.socket.on('reconnect', () => {
                console.log('Reconnected to monitoring WebSocket');
                this.showConnectionStatus('connected');
            });

            this.socket.on('error', (error) => {
                console.error('WebSocket error:', error);
                reject(error);
            });

            this.socket.on('activity', (activity) => {
                console.log('📊 Received activity event:', activity);
                this.addActivity(activity);
            });

            this.socket.on('stats', (stats) => {
                console.log('📈 Received stats update:', stats);
                this.updateStats(stats);
            });

            this.socket.on('players', (players) => {
                console.log('👥 Received players update:', players.length, 'players');
                this.updatePlayersList(players);
            });

            this.socket.on('phrases', (phrases) => {
                console.log('📝 Received phrases update:', phrases.length, 'phrases');
                this.updatePhrasesList(phrases);
            });

            setTimeout(() => {
                if (!this.socket.connected) {
                    reject(new Error('WebSocket connection timeout'));
                }
            }, 10000);
        });
    }

    async loadInitialData() {
        try {
            const [playersResponse, statsResponse] = await Promise.all([
                apiClient.get('/players/online'),
                apiClient.get('/stats')
            ]);

            this.updatePlayersList(playersResponse.players);
            this.updateStats(statsResponse);
        } catch (error) {
            console.error('Failed to load initial data:', error);
        }
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
        this.stats = { ...this.stats, ...stats };
        
        document.getElementById('online-players').textContent = this.stats.onlinePlayers;
        document.getElementById('active-phrases').textContent = this.stats.activePhrases;
        document.getElementById('phrases-today').textContent = this.stats.phrasesToday;
        document.getElementById('completion-rate').textContent = `${this.stats.completionRate}%`;
    }

    updatePlayersList(players) {
        const playersList = document.getElementById('players-list');
        
        if (players.length === 0) {
            playersList.innerHTML = '<div class="no-data">No players online</div>';
            return;
        }

        playersList.innerHTML = players.map(player => `
            <div class="player-item">
                <div class="player-name">${player.name}</div>
                <div class="player-stats">
                    <span class="status-indicator status-online">Online</span>
                    <span>${player.phrasesCompleted || 0} phrases</span>
                </div>
            </div>
        `).join('');
    }

    updatePhrasesList(phrases) {
        const phrasesList = document.getElementById('phrases-list');
        
        if (phrases.length === 0) {
            phrasesList.innerHTML = '<div class="no-data">No recent phrases</div>';
            return;
        }

        phrasesList.innerHTML = phrases.map(phrase => {
            // Convert numeric difficulty to descriptive level
            const getDifficultyLevel = (score) => {
                if (!score) return 'unknown';
                if (score <= 20) return 'easy';
                if (score <= 50) return 'medium';
                if (score <= 80) return 'hard';
                return 'expert';
            };
            
            // Convert language code to flag emoji
            const getLanguageFlag = (langCode) => {
                const flags = {
                    'EN': '🇺🇸',
                    'ES': '🇪🇸',
                    'FR': '🇫🇷',
                    'DE': '🇩🇪',
                    'IT': '🇮🇹',
                    'PT': '🇵🇹',
                    'RU': '🇷🇺',
                    'ZH': '🇨🇳',
                    'JA': '🇯🇵',
                    'KO': '🇰🇷',
                    'AR': '🇸🇦',
                    'HI': '🇮🇳',
                    'NL': '🇳🇱',
                    'SV': '🇸🇪',
                    'NO': '🇳🇴',
                    'DA': '🇩🇰',
                    'FI': '🇫🇮',
                    'PL': '🇵🇱',
                    'TR': '🇹🇷',
                    'HU': '🇭🇺',
                    'CS': '🇨🇿',
                    'SK': '🇸🇰',
                    'HR': '🇭🇷',
                    'SR': '🇷🇸',
                    'BG': '🇧🇬',
                    'RO': '🇷🇴',
                    'EL': '🇬🇷',
                    'HE': '🇮🇱',
                    'TH': '🇹🇭',
                    'VI': '🇻🇳',
                    'ID': '🇮🇩',
                    'MS': '🇲🇾',
                    'UK': '🇺🇦',
                    'LT': '🇱🇹',
                    'LV': '🇱🇻',
                    'ET': '🇪🇪',
                    'SL': '🇸🇮',
                    'MT': '🇲🇹',
                    'IS': '🇮🇸'
                };
                return flags[langCode?.toUpperCase()] || '🏳️';
            };
            
            const difficultyLevel = getDifficultyLevel(phrase.difficulty);
            const difficultyDisplay = phrase.difficulty ? `${phrase.difficulty} pts` : 'N/A';
            const languageFlag = getLanguageFlag(phrase.language || 'EN');
            
            return `
                <div class="phrase-item">
                    <div class="phrase-text">${phrase.text}${phrase.hint ? ` (${phrase.hint})` : ''}</div>
                    <div class="phrase-author">by ${phrase.authorName || 'System'}</div>
                    <div class="phrase-meta">
                        <span class="difficulty-indicator difficulty-${difficultyLevel}">
                            ${difficultyDisplay}
                        </span>
                        <span class="language-flag">${languageFlag}</span>
                    </div>
                </div>
            `;
        }).join('');
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