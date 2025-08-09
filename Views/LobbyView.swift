import SwiftUI
import Foundation

struct LobbyView: View {
    @ObservedObject var gameModel: GameModel
    @State private var selectedLeaderboardPeriod: String = "alltime"
    @State private var showingGame = false
    @State private var leaderboardData: [LeaderboardEntry] = []
    @State private var playerStats: PlayerStats?
    @State private var onlinePlayersCount: Int = 0
    @State private var isLoadingData = false
    @State private var isLoadingLeaderboard = false
    @State private var refreshTimer: Timer?
    @State private var serviceHealthTimer: Timer?
    @State private var contributionLink: String = ""
    @State private var isGeneratingLink = false
    @State private var showingShareSheet = false
    @State private var showingLegends = false
    @State private var isLinkGeneratorServiceHealthy = false
    @State private var isCheckingServiceHealth = true
    
    private let linkGeneratorService = LinkGeneratorService()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Title section
                    titleSection
                    
                    // Header with welcome message
                    headerSection
                    
                    // Online players count
                    onlinePlayersSection
                    
                    // Custom phrases waiting section
                    customPhrasesWaitingSection
                    
                    // Start Playing button
                    startPlayingButton
                    
                    // Personal statistics
                    personalStatsSection
                    
                    // Rarest emojis section
                    if let rarestEmojis = playerStats?.rarestEmojis, !rarestEmojis.isEmpty {
                        rarestEmojisSection(emojis: rarestEmojis)
                    }
                    
                    // Contribution link generator
                    contributionLinkSection
                    
                    // Leaderboards
                    leaderboardsSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 0)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .refreshable {
                await refreshData()
            }
        }
        .onAppear {
            print("🟢 LOBBY: LobbyView appeared!")
            DebugLogger.shared.ui("LobbyView appeared - initializing data")
            
            // Only load data if we have a player ID, otherwise wait for onChange
            if gameModel.playerId != nil {
                Task {
                    await loadInitialData()
                    await checkLinkGeneratorServiceHealth()
                }
            }
        }
        .onChange(of: gameModel.playerId) { oldValue, newValue in
            if newValue != nil && oldValue == nil {
                // Player just logged in, load data for first time
                print("🟢 LOBBY: Player logged in, loading data")
                DebugLogger.shared.info("Player logged in, loading lobby data")
                Task {
                    // Small delay to ensure network manager is fully set up
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await loadInitialData()
                    await checkLinkGeneratorServiceHealth()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
            serviceHealthTimer?.invalidate()
            serviceHealthTimer = nil
        }
        .fullScreenCover(isPresented: $showingGame, onDismiss: {
            // Refresh data when returning from game
            Task {
                await refreshData()
            }
        }) {
            PhysicsGameView(gameModel: gameModel, showingGame: $showingGame)
        }
        .sheet(isPresented: $showingLegends) {
            LegendsView(gameModel: gameModel)
        }
        .alert("Connection Issue", isPresented: $gameModel.showRateLimitAlert) {
            Button("Log Out") {
                gameModel.showRateLimitAlert = false
                gameModel.rateLimitMessage = ""
                
                // Clear user session and force re-login for rate limiting
                Task { @MainActor in
                    UserDefaults.standard.removeObject(forKey: "playerName")
                    NetworkManager.shared.currentPlayer = nil
                    NetworkManager.shared.isConnected = false
                    NetworkManager.shared.connectionStatus = .disconnected
                    print("🔴 RATE LIMIT LOGOUT: Cleared player session, should trigger registration screen")
                }
            }
        } message: {
            Text(gameModel.rateLimitMessage)
        }
    }
    
    // MARK: - Title Section
    private var titleSection: some View {
        VStack(spacing: 12) {
            // Main title
            Text("Anagram Game")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Mission statement
            Text("Do you have what it takes to become a Legend?")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let playerName = gameModel.playerName {
                let isFirstTime = UserDefaults.standard.bool(forKey: "isFirstLogin")
                
                // Use skill title if available, otherwise use default welcome message
                if let skillTitle = playerStats?.skillTitle {
                    Text("Welcome \(playerName) the \(skillTitle)!")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(isFirstTime ? 
                         "Welcome, \(playerName)!" : 
                         "Welcome back, \(playerName)!")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
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
    
    // MARK: - Rarest Emojis Section
    @State private var isEmojiSectionExpanded = false
    
    private func rarestEmojisSection(emojis: [PlayerRareEmoji]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Your Emoji Collection")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Text("Your \(emojis.count) collected emojis (rarest first)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Show up to 8 emojis in 2 rows by default, 16 when expanded
            let displayEmojis = isEmojiSectionExpanded ? Array(emojis.prefix(16)) : Array(emojis.prefix(8))
            let columns = Array(repeating: GridItem(.flexible()), count: 8)
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(displayEmojis, id: \.emojiCharacter) { emoji in
                    VStack(spacing: 4) {
                        Text(emoji.emojiCharacter)
                            .font(.title3)
                        
                        // Rarity indicator dot
                        Circle()
                            .fill(rarityColor(for: emoji.rarityTier))
                            .frame(width: 4, height: 4)
                        
                        Text("\(emoji.dropRate, specifier: "%.1f")%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 35, height: 55)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(6)
                }
            }
            
            // Show expand/collapse button if there are more than 8 emojis
            if emojis.count > 8 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isEmojiSectionExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(isEmojiSectionExpanded ? "Show Less" : "Show More (\(min(emojis.count, 16)) total)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: isEmojiSectionExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func rarityColor(for tier: String) -> Color {
        switch tier.lowercased() {
        case "legendary": return .yellow
        case "mythic": return .purple
        case "epic": return .pink
        case "rare": return .blue
        case "uncommon": return .green
        case "common": return .gray
        default: return .gray
        }
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
                Text("All Time").tag("alltime")
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
            
            // Meet the Legends link
            HStack {
                Spacer()
                Button(action: {
                    showingLegends = true
                }) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                        Text("Meet the Legends")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                }
                Spacer()
            }
            .padding(.top, 8)
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
                Text("Get Custom Phrases")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                // Service status indicator
                serviceStatusIndicator
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
                    .background(isLinkGeneratorServiceHealthy ? Color.blue : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(isGeneratingLink || !isLinkGeneratorServiceHealthy)
                
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
    
    // MARK: - Service Status Indicator
    private var serviceStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isCheckingServiceHealth ? Color.orange : (isLinkGeneratorServiceHealthy ? Color.green : Color.red))
                .frame(width: 8, height: 8)
            
            Text(isCheckingServiceHealth ? "Checking..." : (isLinkGeneratorServiceHealthy ? "Online" : "Offline"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Service Health Check
    private func checkLinkGeneratorServiceHealth() async {
        DebugLogger.shared.network("Checking link generator service health")
        
        await MainActor.run {
            isCheckingServiceHealth = true
        }
        
        let isHealthy = await linkGeneratorService.performHealthCheck()
        
        await MainActor.run {
            isLinkGeneratorServiceHealthy = isHealthy
            isCheckingServiceHealth = false
        }
        
        DebugLogger.shared.network("Link generator service health: \(isHealthy ? "healthy" : "unhealthy")")
    }
    
    private func startServiceHealthMonitoring() {
        // Check service health every 5 minutes (reduced to prevent rate limiting)
        serviceHealthTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            Task {
                await checkLinkGeneratorServiceHealth()
            }
        }
    }
    
    // MARK: - Contribution Link Functions
    private func generateContributionLink() async {
        guard let currentPlayer = NetworkManager.shared.currentPlayer else {
            DebugLogger.shared.error("No current player available for generating contribution link")
            return
        }
        
        await MainActor.run {
            isGeneratingLink = true
        }
        
        do {
            let shareableUrl = try await linkGeneratorService.generateContributionLink(
                playerId: currentPlayer.id,
                expirationHours: 24,
                maxUses: 3
            )
            
            await MainActor.run {
                self.contributionLink = shareableUrl
                self.isGeneratingLink = false
            }
            
        } catch {
            DebugLogger.shared.error("Error generating contribution link: \(error)")
            await MainActor.run {
                isGeneratingLink = false
            }
        }
    }
    
    // MARK: - Data Loading Functions
    private func loadInitialData() async {
        print("🔄 LOBBY: Starting loadInitialData")
        isLoadingData = true
        
        // Check if network manager is available
        guard gameModel.networkManager != nil else {
            print("❌ LOBBY: Cannot load data - networkManager is nil")
            isLoadingData = false
            return
        }
        
        // Load critical data first (stats and leaderboard)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPlayerStats() }
            group.addTask { await self.loadLeaderboard() }
            group.addTask { await self.loadOnlinePlayersCount() }
        }
        
        isLoadingData = false
        print("✅ LOBBY: Finished loadInitialData")
        
        // Start periodic service health checks
        await MainActor.run {
            startServiceHealthMonitoring()
        }
        
        // Load phrases after critical data is loaded to avoid interference
        await loadCustomPhrases()
    }
    
    private func refreshData() async {
        await loadInitialData()
        await checkLinkGeneratorServiceHealth()
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
        DebugLogger.shared.network("Loading player stats for playerId: \(playerId)")
        
        do {
            let stats = try await networkManager.getPlayerStats(playerId: playerId)
            await MainActor.run {
                self.playerStats = stats
                // Log the scores for debugging
                DebugLogger.shared.info("SCORE COMPARISON: gameModel=\(gameModel.playerTotalScore), server=\(stats.totalScore)")
                print("🔍 SCORE COMPARISON: gameModel=\(gameModel.playerTotalScore), server=\(stats.totalScore)")
                
                // Synchronize gameModel's playerTotalScore with server-authoritative score
                if gameModel.playerTotalScore != stats.totalScore {
                    print("🔄 SYNC: Updating gameModel total score from \(gameModel.playerTotalScore) to \(stats.totalScore)")
                    DebugLogger.shared.info("SYNC: Updating gameModel total score from \(gameModel.playerTotalScore) to \(stats.totalScore)")
                    gameModel.playerTotalScore = stats.totalScore
                } else {
                    print("✅ SYNC: Scores already match - no sync needed")
                    DebugLogger.shared.info("SYNC: Scores already match - no sync needed")
                }
            }
            print("✅ Successfully loaded player stats and synchronized total score")
            DebugLogger.shared.network("Successfully loaded player stats and synchronized total score")
        } catch {
            print("❌ Failed to load player stats: \(error)")
            DebugLogger.shared.error("Failed to load player stats: \(error)")
        }
    }
    
    private func loadLeaderboard() async {
        guard let networkManager = gameModel.networkManager else { 
            print("❌ loadLeaderboard: gameModel.networkManager is nil")
            return 
        }
        
        print("📊 Loading leaderboard for period: \(selectedLeaderboardPeriod)")
        
        do {
            let leaderboard = try await networkManager.getLeaderboard(period: selectedLeaderboardPeriod)
            print("✅ Leaderboard loaded with \(leaderboard.count) entries")
        DebugLogger.shared.network("Leaderboard loaded with \(leaderboard.count) entries for period: \(selectedLeaderboardPeriod)")
            await MainActor.run {
                self.leaderboardData = leaderboard
            }
        } catch {
            print("❌ Failed to load leaderboard: \(error)")
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