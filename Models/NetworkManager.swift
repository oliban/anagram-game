import Foundation
import Network
import UIKit
import SocketIO

// Import all the service and model files
// Note: These files need to be added to the Xcode project

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
        return await playerService.registerPlayer(name: name)
    }
    
    func registerPlayerBool(name: String) async -> Bool {
        return await playerService.registerPlayerBool(name: name)
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
    
    func createCustomPhrase(content: String, playerId: String, targetId: String?, language: String = "en") async throws -> CustomPhrase {
        return try await phraseService.createCustomPhrase(content: content, playerId: playerId, targetId: targetId, language: language)
    }
    
    func fetchPhrasesForCurrentPlayer(level: Int? = nil) async -> [CustomPhrase] {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player registered")
            return []
        }
        
        // Build URL with optional level parameter
        var urlString = "\(AppConfig.baseURL)/api/phrases/for/\(currentPlayer.id)"
        if let level = level {
            urlString += "?level=\(level)"
            print("🎯 PHRASE: Fetching phrases for player level \(level)")
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ PHRASE: Invalid URL for fetching phrases")
            return []
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        let urlSession = URLSession(configuration: config)
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ PHRASE: Failed to fetch phrases. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let phrasesData = jsonResponse["phrases"] {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: phrasesData)
                    let phrases = try JSONDecoder().decode([CustomPhrase].self, from: jsonData)
                    print("🔍 PHRASE: Successfully decoded \(phrases.count) phrases")
                    return phrases
                } catch {
                    print("❌ PHRASE: JSON decoding failed: \(error)")
                    return []
                }
            }
            
            return []
        } catch {
            print("❌ PHRASE: Error fetching phrases: \(error)")
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
                language: language
            )
            print("✅ ENHANCED PHRASE: Successfully created enhanced phrase")
            return true
        } catch {
            print("❌ ENHANCED PHRASE: Error creating enhanced phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func completePhrase(phraseId: String, completionTime: Int = 0) async -> CompletionResult? {
        guard let currentPlayer = currentPlayer else {
            print("❌ COMPLETE: No current player to complete phrase")
            return nil
        }
        
        do {
            return try await phraseService.completePhraseOnServer(
                phraseId: phraseId,
                playerId: currentPlayer.id,
                hintsUsed: 0,
                completionTime: completionTime
            )
        } catch {
            print("❌ COMPLETE: Error completing phrase: \(error.localizedDescription)")
            return nil
        }
    }
    
    func skipPhrase(phraseId: String) async -> Bool {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player to skip phrase")
            return false
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/api/phrases/\(phraseId)/skip") else {
            print("❌ PHRASE: Invalid URL for skipping phrase")
            return false
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        let urlSession = URLSession(configuration: config)
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10.0
            
            // Add playerId in request body as required by server
            let requestBody = ["playerId": currentPlayer.id]
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (_, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("⏭️ PHRASE: Successfully skipped phrase \(phraseId)")
                return true
            } else {
                print("❌ PHRASE: Failed to skip phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
        } catch {
            print("❌ PHRASE: Error skipping phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func useHint(phraseId: String, playerId: String) async throws -> HintResponse {
        return try await phraseService.useHint(phraseId: phraseId, playerId: playerId)
    }
    
    func useHint(phraseId: String, level: Int) async -> HintResponse? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player to use hint")
            return nil
        }
        
        do {
            return try await phraseService.useHint(phraseId: phraseId, playerId: currentPlayer.id)
        } catch {
            print("❌ HINT: Error using hint: \(error.localizedDescription)")
            return nil
        }
    }
    
    func getHintStatus(phraseId: String) async -> HintStatus? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player for hint status")
            return nil
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/api/phrases/\(phraseId)/hints/status?playerId=\(currentPlayer.id)") else {
            print("❌ HINT: Invalid URL for hint status")
            return nil
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        let urlSession = URLSession(configuration: config)
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ HINT: Failed to get hint status. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            // Parse the response which has hintStatus nested inside
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hintStatusData = jsonResponse["hintStatus"] {
                let hintStatusJSON = try JSONSerialization.data(withJSONObject: hintStatusData)
                let hintStatus = try JSONDecoder().decode(HintStatus.self, from: hintStatusJSON)
                print("🔍 HINT: Got hint status for \(phraseId)")
                return hintStatus
            }
            
            print("❌ HINT: Invalid hint status response format")
            return nil
            
        } catch {
            print("❌ HINT: Error getting hint status: \(error.localizedDescription)")
            return nil
        }
    }
    
    func getPhrasePreview(phraseId: String) async -> PhrasePreview? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player for phrase preview")
            return nil
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/api/phrases/\(phraseId)/preview?playerId=\(currentPlayer.id)") else {
            print("❌ HINT: Invalid URL for phrase preview")
            return nil
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        let urlSession = URLSession(configuration: config)
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ HINT: Failed to get phrase preview. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let preview = try JSONDecoder().decode(PhrasePreview.self, from: data)
            print("🔍 HINT: Got phrase preview for \(phraseId)")
            return preview
            
        } catch {
            print("❌ HINT: Error getting phrase preview: \(error.localizedDescription)")
            return nil
        }
    }
    
    func completePhraseOnServer(phraseId: String, playerId: String, hintsUsed: Int, completionTime: Int) async throws -> CompletionResult {
        return try await phraseService.completePhraseOnServer(phraseId: phraseId, playerId: playerId, hintsUsed: hintsUsed, completionTime: completionTime)
    }
    
    func consumePhrase(phraseId: String) async -> Bool {
        guard let url = URL(string: "\(AppConfig.baseURL)/api/phrases/\(phraseId)/consume") else {
            print("❌ PHRASE: Invalid URL for consuming phrase")
            return false
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        let urlSession = URLSession(configuration: config)
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ PHRASE: Successfully consumed phrase \(phraseId)")
                return true
            } else {
                print("❌ PHRASE: Failed to consume phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
        } catch {
            print("❌ PHRASE: Error consuming phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func clearCachedPhrase() async {
        await MainActor.run {
            self.lastReceivedPhrase = nil
            self.hasNewPhrase = false
            self.justReceivedPhrase = nil
        }
        print("🧹 PHRASE: Cleared cached phrase data")
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
    
    func getLegendPlayers() async throws -> [LegendPlayer] {
        let response = try await leaderboardService.fetchLegendPlayers()
        return response.players
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