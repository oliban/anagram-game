import Foundation
import Network
import UIKit
import SocketIO

// MARK: - Configuration
// Configuration is now loaded from NetworkConfiguration.swift

// Models are now defined in NetworkModels.swift to avoid duplication

@MainActor
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    // Service instances
    private let connectionService = ConnectionService()
    private let playerService = PlayerService()
    private let phraseService = PhraseService()
    private let leaderboardService = LeaderboardService()
    private let difficultyService = DifficultyAnalysisService()
    
    // Published properties for UI
    @Published var isConnected: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var currentPlayer: Player?
    @Published var onlinePlayers: [Player] = []
    @Published var currentPhrase: CustomPhrase?
    @Published var hintStatus: HintStatus?
    @Published var dailyLeaderboard: [LeaderboardEntry] = []
    @Published var weeklyLeaderboard: [LeaderboardEntry] = []
    @Published var allTimeLeaderboard: [LeaderboardEntry] = []
    @Published var legendPlayers: [LegendPlayer] = []
    
    private init() {
        setupServiceDelegates()
        bindServices()
    }
    
    // MARK: - Service Setup
    
    private func setupServiceDelegates() {
        connectionService.playerDelegate = playerService
        connectionService.phraseDelegate = phraseService
    }
    
    private func bindServices() {
        // Bind connection service
        connectionService.$isConnected
            .assign(to: &$isConnected)
        
        connectionService.$connectionStatus
            .assign(to: &$connectionStatus)
        
        // Bind player service
        playerService.$currentPlayer
            .assign(to: &$currentPlayer)
        
        playerService.$onlinePlayers
            .assign(to: &$onlinePlayers)
        
        // Bind phrase service
        phraseService.$currentPhrase
            .assign(to: &$currentPhrase)
        
        phraseService.$hintStatus
            .assign(to: &$hintStatus)
        
        // Bind leaderboard service
        leaderboardService.$dailyLeaderboard
            .assign(to: &$dailyLeaderboard)
        
        leaderboardService.$weeklyLeaderboard
            .assign(to: &$weeklyLeaderboard)
        
        leaderboardService.$allTimeLeaderboard
            .assign(to: &$allTimeLeaderboard)
        
        leaderboardService.$legendPlayers
            .assign(to: &$legendPlayers)
    }
    
    // MARK: - Connection Management
    
    func connect(playerId: String) {
        connectionService.connect(playerId: playerId)
    }
    
    func disconnect() {
        connectionService.disconnect()
    }
    
    func connect() {
        // Legacy method that creates a basic connection without player ID
        print("📡 LEGACY: Basic connect() called - setting up socket")
        if let currentPlayer = currentPlayer {
            connectionService.connect(playerId: currentPlayer.id)
        } else {
            print("❌ LEGACY: No current player for basic connect()")
        }
    }
    
    func testConnection() async -> Result<Bool, NetworkError> {
        return await difficultyService.performHealthCheck() ? .success(true) : .failure(.serverOffline)
    }
    
    // MARK: - Player Management
    
    func registerPlayer(name: String) async -> RegistrationResult {
        let result = await playerService.registerPlayer(name: name)
        
        // If registration successful, establish WebSocket connection
        if case .success = result {
            // Get player directly from service to avoid binding timing issues
            if let servicePlayer = playerService.currentPlayer {
                print("🔌 NETWORK: About to initiate WebSocket connection for player: \(servicePlayer.id)")
                connectionService.connect(playerId: servicePlayer.id)
                print("🔌 NETWORK: WebSocket connection initiated after successful registration")
            } else {
                print("❌ NETWORK: Success but no currentPlayer in service! NetworkManager: \(currentPlayer?.id ?? "nil")")
            }
        } else {
            print("❌ NETWORK: WebSocket connection NOT initiated. Result: \(result), CurrentPlayer: \(currentPlayer?.id ?? "nil")")
        }
        
        return result
    }
    
    func registerPlayerBool(name: String) async -> Bool {
        print("🔍 NETWORK: registerPlayerBool called for name: \(name)")
        let result = await playerService.registerPlayer(name: name)
        print("🔍 NETWORK: registerPlayerBool result: \(result)")
        print("🔍 NETWORK: currentPlayer after registration: \(currentPlayer?.name ?? "nil")")
        
        // If registration successful, establish WebSocket connection  
        if case .success = result {
            // Get player directly from service to avoid binding timing issues
            if let servicePlayer = playerService.currentPlayer {
                print("🔌 NETWORK: About to initiate WebSocket connection for player: \(servicePlayer.id)")
                connectionService.connect(playerId: servicePlayer.id)
                print("🔌 NETWORK: WebSocket connection initiated after successful registration")
                return true
            } else {
                print("❌ NETWORK: Success but no currentPlayer in service! NetworkManager: \(currentPlayer?.id ?? "nil")")
            }
        } else {
            print("❌ NETWORK: WebSocket connection NOT initiated. Result: \(result), CurrentPlayer: \(currentPlayer?.id ?? "nil")")
        }
        
        return false
    }
    
    func fetchOnlinePlayers() async {
        await playerService.fetchOnlinePlayers()
    }
    
    func getPlayerStats(playerId: String) async throws -> PlayerStats {
        return try await playerService.getPlayerStats(playerId: playerId)
    }
    
    func getOnlinePlayersCount() async throws -> Int {
        return try await playerService.getOnlinePlayersCount()
    }
    
    func startPeriodicPlayerListFetch() {
        playerService.startPeriodicPlayerListFetch()
    }
    
    func stopPeriodicPlayerListFetch() {
        playerService.stopPeriodicPlayerListFetch()
    }
    
    // MARK: - Phrase Management
    
    func fetchPhraseForPlayer(playerId: String) async throws -> PhrasePreview {
        return try await phraseService.fetchPhraseForPlayer(playerId: playerId)
    }
    
    func createCustomPhrase(content: String, playerId: String, targetId: String?, hint: String = "", language: String = "en") async throws -> CustomPhrase {
        return try await phraseService.createCustomPhrase(content: content, playerId: playerId, targetId: targetId, hint: hint, language: language)
    }
    
    func fetchPhrasesForCurrentPlayer(level: Int? = nil) async -> [CustomPhrase] {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player registered")
            return []
        }
        
        // Delegate to PhraseService instead of duplicating the logic
        do {
            return try await phraseService.fetchPhrasesForPlayer(playerId: currentPlayer.id, level: level)
        } catch {
            print("❌ PHRASE: Error fetching phrases via service: \(error)")
            return []
        }
    }
    
    func createGlobalPhrase(content: String, hint: String, language: String = "en") async -> Bool {
        guard let currentPlayer = currentPlayer else {
            print("❌ GLOBAL PHRASE: No current player registered")
            return false
        }
        
        do {
            _ = try await phraseService.createCustomPhrase(
                content: content,
                playerId: currentPlayer.id,
                targetId: nil, // Global phrase
                hint: "", // No hint for global phrases created through this method
                language: language
            )
            print("✅ GLOBAL PHRASE: Successfully created global phrase")
            return true
        } catch {
            print("❌ GLOBAL PHRASE: Error creating global phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func createEnhancedPhrase(content: String, hint: String, targetIds: [String], isGlobal: Bool, language: String = "en") async -> Bool {
        guard let currentPlayer = currentPlayer else {
            print("❌ ENHANCED PHRASE: No current player registered")
            return false
        }
        
        // For enhanced phrases, we'll create them as custom phrases
        // If it's global, targetId is nil; if targeted, use first targetId
        let targetId = isGlobal ? nil : targetIds.first
        
        do {
            _ = try await phraseService.createCustomPhrase(
                content: content,
                playerId: currentPlayer.id,
                targetId: targetId,
                hint: hint,
                language: language
            )
            print("✅ ENHANCED PHRASE: Successfully created enhanced phrase")
            return true
        } catch {
            print("❌ ENHANCED PHRASE: Error creating enhanced phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func completePhrase(phraseId: String, hintsUsed: Int = 0, completionTime: Int = 0, celebrationEmojis: [EmojiCatalogItem] = []) async -> CompletionResult? {
        guard let currentPlayer = currentPlayer else {
            print("❌ COMPLETE: No current player to complete phrase")
            return nil
        }
        
        do {
            return try await phraseService.completePhraseOnServer(
                phraseId: phraseId,
                playerId: currentPlayer.id,
                hintsUsed: hintsUsed,
                completionTime: completionTime,
                celebrationEmojis: celebrationEmojis
            )
        } catch {
            print("❌ COMPLETE: Error completing phrase: \(error.localizedDescription)")
            return nil
        }
    }
    
    func useHint(phraseId: String, playerId: String) async throws -> HintResponse {
        return try await phraseService.useHint(phraseId: phraseId, playerId: playerId)
    }
    
    
    func completePhraseOnServer(phraseId: String, playerId: String, hintsUsed: Int, completionTime: Int, celebrationEmojis: [EmojiCatalogItem] = []) async throws -> CompletionResult {
        return try await phraseService.completePhraseOnServer(phraseId: phraseId, playerId: playerId, hintsUsed: hintsUsed, completionTime: completionTime, celebrationEmojis: celebrationEmojis)
    }
    
    func skipPhrase(phraseId: String) async -> Bool {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player to skip phrase")
            return false
        }
        
        let urlString = "\(AppConfig.baseURL)/api/phrases/\(phraseId)/skip"
        guard let url = URL(string: urlString) else {
            print("❌ PHRASE: Invalid skip URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let body = ["playerId": currentPlayer.id]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let success = httpResponse.statusCode == 200
                print("\(success ? "✅" : "❌") PHRASE: Skip phrase response: \(httpResponse.statusCode)")
                return success
            }
            return false
        } catch {
            print("❌ PHRASE: Failed to skip phrase: \(error)")
            return false
        }
    }
    
    // MARK: - Leaderboard Management
    
    func fetchDailyLeaderboard() async throws -> [LeaderboardEntry] {
        return try await leaderboardService.fetchDailyLeaderboard()
    }
    
    func fetchWeeklyLeaderboard() async throws -> [LeaderboardEntry] {
        return try await leaderboardService.fetchWeeklyLeaderboard()
    }
    
    func fetchAllTimeLeaderboard() async throws -> [LeaderboardEntry] {
        return try await leaderboardService.fetchAllTimeLeaderboard()
    }
    
    func fetchLegendPlayers() async throws -> LegendPlayersResponse {
        return try await leaderboardService.fetchLegendPlayers()
    }
    
    func getPlayerRanking(playerId: String, in leaderboardType: String) async throws -> Int? {
        return try await leaderboardService.getPlayerRanking(playerId: playerId, in: leaderboardType)
    }
    
    func getLegendPlayers() async throws -> LegendPlayersResponse {
        return try await leaderboardService.fetchLegendPlayers()
    }
    
    func getLeaderboard(period: String, limit: Int = 10) async throws -> [LeaderboardEntry] {
        switch period {
        case "daily":
            return try await leaderboardService.fetchDailyLeaderboard()
        case "weekly":
            return try await leaderboardService.fetchWeeklyLeaderboard()
        case "alltime":
            return try await leaderboardService.fetchAllTimeLeaderboard()
        default:
            return try await leaderboardService.fetchDailyLeaderboard()
        }
    }
    
    // MARK: - Difficulty Analysis & Configuration
    
    func fetchServerConfig() async throws -> ServerConfig {
        return try await difficultyService.fetchServerConfig()
    }
    
    func analyzePhrasesDifficulty(phrases: [String], language: String = "en") async throws -> [DifficultyAnalysis] {
        return try await difficultyService.analyzePhrasesDifficulty(phrases: phrases, language: language)
    }
    
    func analyzeSinglePhraseDifficulty(phrase: String, language: String = "en") async throws -> DifficultyAnalysis {
        return try await difficultyService.analyzeSinglePhraseDifficulty(phrase: phrase, language: language)
    }
    
    func performHealthCheck() async -> Bool {
        return await difficultyService.performHealthCheck()
    }
    
    func analyzeDifficulty(phrase: String, language: String = "en") async -> DifficultyAnalysis? {
        do {
            return try await difficultyService.analyzeSinglePhraseDifficulty(phrase: phrase, language: language)
        } catch {
            print("❌ DIFFICULTY: Error analyzing difficulty: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Game Integration Properties
    
    // Debug properties
    @Published var lastError: String? = nil
    var debugServerURL: String {
        return AppConfig.baseURL
    }
    
    // Reference to GameModel for accessing messageTileSpawner
    weak var gameModel: GameModel?
    
    // Push-based phrase delivery (required for GameModel integration)
    @Published var hasNewPhrase: Bool = false
    @Published var justReceivedPhrase: CustomPhrase? = nil
    @Published var lastReceivedPhrase: CustomPhrase? = nil
    
    // MARK: - Client-Side Difficulty Analysis (Static Method)
    
    static func analyzeDifficultyClientSide(phrase: String, language: String = "en") -> DifficultyAnalysis {
        print("🔍 CLIENT DIFFICULTY: Analyzing '\(phrase)' with language '\(language)'")
        
        // Simple scoring based on length and complexity
        let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        let letterCount = phrase.replacingOccurrences(of: " ", with: "").count
        
        // Simple scoring based on length and complexity
        let baseScore = Double(letterCount * 5 + words.count * 10)
        let finalScore = min(max(baseScore, 1.0), 100.0)
        
        print("⚠️ CLIENT DIFFICULTY: Calculated score \(finalScore) for '\(phrase)' (\(language)) - CLIENT ALGORITHM")
        
        return DifficultyAnalysis(
            phrase: phrase,
            language: language,
            score: finalScore,
            difficulty: finalScore > 50 ? "Medium" : "Easy",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
}