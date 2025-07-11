import SwiftUI
import Foundation

struct LobbyView: View {
    @ObservedObject var gameModel: GameModel
    @State private var selectedLeaderboardPeriod: String = "daily"
    @State private var showingGame = false
    @State private var leaderboardData: [LeaderboardEntry] = []
    @State private var playerStats: PlayerStats?
    @State private var onlinePlayersCount: Int = 0
    @State private var isLoadingData = false
    @State private var isLoadingLeaderboard = false
    @State private var refreshTimer: Timer?
    @State private var contributionLink: String = ""
    @State private var isGeneratingLink = false
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with welcome message
                    headerSection
                    
                    // Online players count
                    onlinePlayersSection
                    
                    // Custom phrases waiting section
                    customPhrasesWaitingSection
                    
                    // Contribution link generator
                    contributionLinkSection
                    
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
            print("🟢 LOBBY: LobbyView appeared!")
            Task {
                await loadInitialData()
            }
            
            // Load custom phrases only once on appear - rely on real-time notifications for updates
            // No periodic timer needed since WebSocket provides real-time updates
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .fullScreenCover(isPresented: $showingGame) {
            PhysicsGameView(gameModel: gameModel, showingGame: $showingGame)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let playerName = gameModel.playerName {
                let isFirstTime = UserDefaults.standard.bool(forKey: "isFirstLogin")
                Text(isFirstTime ? "Welcome, \(playerName)!" : "Welcome back, \(playerName)!")
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
    
    // MARK: - Custom Phrases Waiting Section
    private var customPhrasesWaitingSection: some View {
        Group {
            if gameModel.hasWaitingPhrases {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You have \(gameModel.waitingPhrasesCount) custom phrase\(gameModel.waitingPhrasesCount == 1 ? "" : "s") waiting for you")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("from \(formatSenderNames(gameModel.waitingPhrasesSenders))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
        }
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
                    isLoadingLeaderboard = true
                    await loadLeaderboard()
                    isLoadingLeaderboard = false
                }
            }
            
            // Leaderboard list
            if isLoadingData || isLoadingLeaderboard {
                Text("Loading leaderboard...")
                    .foregroundColor(.secondary)
                    .padding()
            } else if leaderboardData.isEmpty {
                Text("No leaderboard data available")
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
    
    // MARK: - Contribution Link Generator
    private var contributionLinkSection: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "link.badge.plus")
                    .foregroundColor(.blue)
                Text("Share Your Challenge")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Text("Generate a link for others to contribute phrases specifically for you")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await generateContributionLink()
                    }
                }) {
                    HStack {
                        if isGeneratingLink {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(isGeneratingLink ? "Generating..." : "Generate Link")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isGeneratingLink)
                
                if !contributionLink.isEmpty {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            if !contributionLink.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("Generated Link:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Text(contributionLink)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                        .onTapGesture {
                            UIPasteboard.general.string = contributionLink
                        }
                    
                    Text("Tap to copy • Valid for 24 hours • 3 uses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [contributionLink])
        }
    }
    
    // MARK: - Contribution Link Functions
    private func generateContributionLink() async {
        guard let currentPlayer = NetworkManager.shared.currentPlayer else {
            print("❌ No current player available for generating contribution link")
            return
        }
        
        await MainActor.run {
            isGeneratingLink = true
        }
        
        do {
            let requestBody: [String: Any] = [
                "playerId": currentPlayer.id,
                "expirationHours": 24,
                "maxUses": 3
            ]
            
            print("📝 CONTRIBUTION: Request body: \(requestBody)")
            
            guard let url = URL(string: AppConfig.contributionAPIURL) else {
                print("❌ CONTRIBUTION: Invalid URL for contribution request")
                await MainActor.run {
                    isGeneratingLink = false
                }
                return
            }
            
            print("🌐 CONTRIBUTION: Making request to: \(url)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("❌ CONTRIBUTION: Failed to generate contribution link. Status: \(response)")
                if let httpResponse = response as? HTTPURLResponse {
                    print("❌ CONTRIBUTION: Status code: \(httpResponse.statusCode)")
                }
                await MainActor.run {
                    isGeneratingLink = false
                }
                return
            }
            
            print("📊 CONTRIBUTION: Raw response data: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ CONTRIBUTION: Successfully parsed JSON: \(json)")
                
                if let linkData = json["link"] as? [String: Any] {
                    print("✅ CONTRIBUTION: Found link data: \(linkData)")
                    
                    if let shareableUrl = linkData["shareableUrl"] as? String {
                        print("✅ CONTRIBUTION: Found shareableUrl: \(shareableUrl)")
                        
                        await MainActor.run {
                            // Use the base URL from config for sharing
                            self.contributionLink = shareableUrl.replacingOccurrences(of: "http://127.0.0.1:3000", with: AppConfig.contributionBaseURL)
                            self.isGeneratingLink = false
                            print("✅ CONTRIBUTION: Final generated link: \(self.contributionLink)")
                        }
                    } else {
                        print("❌ CONTRIBUTION: No shareableUrl found in linkData")
                        await MainActor.run {
                            isGeneratingLink = false
                        }
                    }
                } else {
                    print("❌ CONTRIBUTION: No link data found in JSON")
                    await MainActor.run {
                        isGeneratingLink = false
                    }
                }
            } else {
                print("❌ CONTRIBUTION: Failed to parse JSON from response data")
                await MainActor.run {
                    isGeneratingLink = false
                }
            }
            
        } catch {
            print("❌ Error generating contribution link: \(error)")
            await MainActor.run {
                isGeneratingLink = false
            }
        }
    }
    
    // MARK: - Data Loading Functions
    private func loadInitialData() async {
        isLoadingData = true
        
        // Load critical data first (stats and leaderboard)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadPlayerStats() }
            group.addTask { await loadLeaderboard() }
            group.addTask { await loadOnlinePlayersCount() }
        }
        
        isLoadingData = false
        
        // Load phrases after critical data is loaded to avoid interference
        await loadCustomPhrases()
    }
    
    private func refreshData() async {
        await loadInitialData()
    }
    
    private func loadPlayerStats() async {
        guard let playerId = gameModel.playerId else { 
            print("❌ loadPlayerStats: gameModel.playerId is nil")
            return 
        }
        
        guard let networkManager = gameModel.networkManager else { 
            print("❌ loadPlayerStats: gameModel.networkManager is nil")
            return 
        }
        
        print("📊 Loading player stats for playerId: \(playerId)")
        
        do {
            let stats = try await networkManager.getPlayerStats(playerId: playerId)
            await MainActor.run {
                self.playerStats = stats
            }
            print("✅ Successfully loaded player stats")
        } catch {
            print("❌ Failed to load player stats: \(error)")
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
    
    private func loadCustomPhrases() async {
        await gameModel.refreshPhrasesForLobby()
    }
    
    // MARK: - Helper Functions
    private func formatSenderNames(_ senders: [String]) -> String {
        // Remove duplicates while preserving order
        let uniqueSenders = Array(NSOrderedSet(array: senders)) as! [String]
        
        if uniqueSenders.isEmpty {
            return ""
        } else if uniqueSenders.count == 1 {
            return uniqueSenders[0]
        } else if uniqueSenders.count == 2 {
            return "\(uniqueSenders[0]) and \(uniqueSenders[1])"
        } else {
            let firstNames = uniqueSenders.prefix(uniqueSenders.count - 1).joined(separator: ", ")
            let lastName = uniqueSenders.last!
            return "\(firstNames) and \(lastName)"
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    LobbyView(gameModel: GameModel())
}