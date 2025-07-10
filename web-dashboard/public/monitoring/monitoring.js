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
        this.setupEventListeners();
        this.showConnectionStatus('connecting');
        
        try {
            await this.connectWebSocket();
            await this.loadInitialData();
            this.showConnectionStatus('connected');
        } catch (error) {
            console.error('Failed to initialize dashboard:', error);
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
            this.socket = io('/monitoring', {
                transports: ['websocket', 'polling'],
                upgrade: true,
                rememberUpgrade: true
            });

            this.socket.on('connect', () => {
                console.log('Connected to monitoring WebSocket');
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
                this.addActivity(activity);
            });

            this.socket.on('stats', (stats) => {
                this.updateStats(stats);
            });

            this.socket.on('players', (players) => {
                this.updatePlayersList(players);
            });

            this.socket.on('phrases', (phrases) => {
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
        const feed = document.getElementById('activity-feed');
        const existingLoading = feed.querySelector('.loading');
        if (existingLoading) {
            existingLoading.remove();
        }

        const activityElement = document.createElement('div');
        activityElement.className = `activity-item ${isNew ? 'new-item' : ''}`;
        activityElement.dataset.type = activity.type;
        activityElement.dataset.timestamp = activity.timestamp.getTime();

        const time = activity.timestamp.toLocaleTimeString('en-US', {
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
                ${activity.details ? `<div class="activity-details">${activity.details}</div>` : ''}
            </div>
        `;

        if (isNew) {
            feed.prepend(activityElement);
        } else {
            feed.appendChild(activityElement);
        }

        if (this.isAutoScrolling && isNew) {
            activityElement.scrollIntoView({ behavior: 'smooth' });
        }

        this.applyFilters();
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

        phrasesList.innerHTML = phrases.map(phrase => `
            <div class="phrase-item">
                <div class="phrase-text">${phrase.text}</div>
                <div class="phrase-meta">
                    <span class="difficulty-indicator difficulty-${phrase.difficulty?.toLowerCase().replace(' ', '-')}">
                        ${phrase.difficulty || 'N/A'}
                    </span>
                    <span>${phrase.language || 'EN'}</span>
                </div>
            </div>
        `).join('');
    }

    applyFilters() {
        const feed = document.getElementById('activity-feed');
        const items = feed.querySelectorAll('.activity-item');
        const now = Date.now();
        
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

        items.forEach(item => {
            const type = item.dataset.type;
            const timestamp = parseInt(item.dataset.timestamp);
            
            const typeVisible = this.filters[type] !== false;
            const timeVisible = timestamp >= cutoffTime;
            
            item.style.display = (typeVisible && timeVisible) ? 'flex' : 'none';
        });
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
    new MonitoringDashboard();
});