import SwiftUI

struct LobbyView: View {
    @ObservedObject var gameModel: GameModel
    @State private var selectedLeaderboardPeriod: String = "daily"
    @State private var showingGame = false
    @State private var leaderboardData: [LeaderboardEntry] = []
    @State private var playerStats: PlayerStats?
    @State private var onlinePlayersCount: Int = 0
    @State private var isLoadingData = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with welcome message
                    headerSection
                    
                    // Online players count
                    onlinePlayersSection
                    
                    // Personal statistics
                    personalStatsSection
                    
                    // Start Playing button
                    startPlayingButton
                    
                    // Leaderboards
                    leaderboardsSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 0)
            }
            .navigationTitle("🏆 Anagram Game")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
        }
        .onAppear {
            Task {
                await loadInitialData()
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            PhysicsGameView(gameModel: gameModel, showingGame: $showingGame)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let playerName = gameModel.playerName {
                Text("Welcome back, \(playerName)!")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Text("Ready to solve some anagrams?")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Online Players Section
    private var onlinePlayersSection: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundColor(.green)
            Text("\(onlinePlayersCount) players online")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Personal Statistics Section
    private var personalStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Your Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if let stats = playerStats {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80)), count: 3), spacing: 12) {
                    StatCard(title: "Daily Score", value: "\(stats.dailyScore)", rank: "#\(stats.dailyRank)")
                    StatCard(title: "Weekly Score", value: "\(stats.weeklyScore)", rank: "#\(stats.weeklyRank)")
                    StatCard(title: "Total Score", value: "\(stats.totalScore)", rank: "#\(stats.totalRank)")
                }
                
                HStack {
                    Spacer()
                    Text("Total phrases completed: \(stats.totalPhrases)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Text("Loading your statistics...")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .frame(minHeight: 120)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Leaderboards Section
    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                Text("Leaderboards")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Period selector
            Picker("Period", selection: $selectedLeaderboardPeriod) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
                Text("All Time").tag("total")
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedLeaderboardPeriod) { _, _ in
                Task {
                    await loadLeaderboard()
                }
            }
            
            // Leaderboard list
            if leaderboardData.isEmpty {
                Text("Loading leaderboard...")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(Array(leaderboardData.prefix(10).enumerated()), id: \.offset) { index, entry in
                    LeaderboardRow(
                        rank: entry.rank,
                        playerName: entry.playerName,
                        score: entry.totalScore,
                        phrasesCompleted: entry.phrasesCompleted,
                        isCurrentPlayer: entry.playerName == gameModel.playerName
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Start Playing Button
    private var startPlayingButton: some View {
        Button(action: {
            showingGame = true
        }) {
            HStack {
                Image(systemName: "play.fill")
                    .font(.title2)
                Text("PLAY")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Data Loading Functions
    private func loadInitialData() async {
        isLoadingData = true
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadPlayerStats() }
            group.addTask { await loadLeaderboard() }
            group.addTask { await loadOnlinePlayersCount() }
        }
        
        isLoadingData = false
    }
    
    private func refreshData() async {
        await loadInitialData()
    }
    
    private func loadPlayerStats() async {
        guard let playerId = gameModel.playerId,
              let networkManager = gameModel.networkManager else { return }
        
        do {
            let stats = try await networkManager.getPlayerStats(playerId: playerId)
            await MainActor.run {
                self.playerStats = stats
            }
        } catch {
            print("Failed to load player stats: \(error)")
        }
    }
    
    private func loadLeaderboard() async {
        guard let networkManager = gameModel.networkManager else { return }
        
        do {
            let leaderboard = try await networkManager.getLeaderboard(period: selectedLeaderboardPeriod)
            await MainActor.run {
                self.leaderboardData = leaderboard
            }
        } catch {
            print("Failed to load leaderboard: \(error)")
        }
    }
    
    private func loadOnlinePlayersCount() async {
        guard let networkManager = gameModel.networkManager else { return }
        
        do {
            let count = try await networkManager.getOnlinePlayersCount()
            await MainActor.run {
                self.onlinePlayersCount = count
            }
        } catch {
            print("Failed to load online players count: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let rank: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(rank)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let playerName: String
    let score: Int
    let phrasesCompleted: Int
    let isCurrentPlayer: Bool
    
    var body: some View {
        HStack {
            // Rank with special styling for top 3
            Text("#\(rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(rankColor)
                .frame(width: 40, alignment: .leading)
            
            // Player name
            Text(playerName)
                .font(.body)
                .fontWeight(isCurrentPlayer ? .bold : .regular)
                .foregroundColor(isCurrentPlayer ? .blue : .primary)
                .lineLimit(1)
            
            Spacer()
            
            // Score and phrases
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(score) pts")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("\(phrasesCompleted) phrases")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isCurrentPlayer ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
}

#Preview {
    LobbyView(gameModel: GameModel())
}