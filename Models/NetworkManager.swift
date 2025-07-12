import Foundation
import Network
import UIKit
import SocketIO

// Player model matching server-side structure
struct Player: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let lastSeen: Date
    let isActive: Bool
    let phrasesCompleted: Int
    
    private enum CodingKeys: String, CodingKey {
        case id, name, lastSeen, isActive, phrasesCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        phrasesCompleted = try container.decode(Int.self, forKey: .phrasesCompleted)
        
        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .lastSeen)
        let formatter = ISO8601DateFormatter()
        lastSeen = formatter.date(from: dateString) ?? Date()
    }
}

// Custom phrase model for multiplayer phrases
struct CustomPhrase: Codable, Identifiable, Equatable {
    let id: String
    let content: String
    let senderId: String
    let targetId: String
    let createdAt: Date
    let isConsumed: Bool
    let senderName: String
    let language: String // Language code for LanguageTile feature
    
    private enum CodingKeys: String, CodingKey {
        case id, content, senderId, targetId, createdAt, isConsumed, senderName, language
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decode(String.self, forKey: .senderId)
        targetId = try container.decode(String.self, forKey: .targetId)
        isConsumed = try container.decode(Bool.self, forKey: .isConsumed)
        senderName = try container.decode(String.self, forKey: .senderName)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en" // Default to English
        
        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        createdAt = formatter.date(from: dateString) ?? Date()
    }
}

// Hint system models for Phase 4.8 integration
struct HintStatus: Codable {
    let hintsUsed: [UsedHint]
    let nextHintLevel: Int?
    let hintsRemaining: Int
    let currentScore: Int
    let nextHintScore: Int?
    let canUseNextHint: Bool
    
    struct UsedHint: Codable {
        let level: Int
        let usedAt: Date
        
        init(level: Int, usedAt: Date) {
            self.level = level
            self.usedAt = usedAt
        }
        
        private enum CodingKeys: String, CodingKey {
            case level, usedAt
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            level = try container.decode(Int.self, forKey: .level)
            
            // Handle date parsing
            let dateString = try container.decode(String.self, forKey: .usedAt)
            let formatter = ISO8601DateFormatter()
            usedAt = formatter.date(from: dateString) ?? Date()
        }
    }
}

struct ScorePreview: Codable {
    let noHints: Int
    let level1: Int
    let level2: Int
    let level3: Int
}

struct HintResponse: Codable {
    let success: Bool
    let hint: HintData
    let scorePreview: ScorePreview
    let timestamp: String
    
    struct HintData: Codable {
        let level: Int
        let content: String
        let currentScore: Int
        let nextHintScore: Int?
        let hintsRemaining: Int
        let canUseNextHint: Bool
    }
}

struct PhrasePreview: Codable {
    let success: Bool
    let phrase: PhraseData
    let timestamp: String
    
    struct PhraseData: Codable {
        let id: String
        let content: String
        let hint: String
        let difficultyLevel: Int
        let isGlobal: Bool
        let hintStatus: HintStatus
        let scorePreview: ScorePreview
    }
}

struct CompletionResult: Codable {
    let success: Bool
    let completion: CompletionData
    let timestamp: String
    
    struct CompletionData: Codable {
        let finalScore: Int
        let hintsUsed: Int
        let completionTime: Int
    }
}

private struct RegistrationRequestBody: Encodable {
    let name: String
}

@MainActor
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isConnected: Bool = false
    @Published var currentPlayer: Player? = nil
    @Published var onlinePlayers: [Player] = []
    // REMOVED: Local phrase caching to fix race conditions
    // @Published var pendingPhrases: [CustomPhrase] = []
    @Published var lastReceivedPhrase: CustomPhrase? = nil
    
    // Push-based phrase delivery
    @Published var hasNewPhrase: Bool = false
    @Published var justReceivedPhrase: CustomPhrase? = nil
    
    
    private let baseURL = "http://192.168.1.133:3000"
    private var urlSession: URLSession
    private var playerListTimer: Timer?
    private var connectionMonitorTimer: Timer?
    private var lastPlayerListFetch: Date = Date.distantPast
    private var isFetchingPlayers: Bool = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
    // Reference to GameModel for accessing messageTileSpawner
    weak var gameModel: GameModel?
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    enum NetworkError: Error, LocalizedError {
        case invalidURL
        case serverOffline
        case connectionFailed
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .serverOffline: return "Server is offline"
            case .connectionFailed: return "Connection failed"
            case .invalidResponse: return "Invalid server response"
            }
        }
    }
    
    private init() {
        // Initialize with basic configuration first
        self.urlSession = URLSession.shared
        
        // Configure URLSession properly
        configureURLSession()

        // Initialize Socket.IO manager
        setupSocketManager()
        
        // Monitor app lifecycle to maintain connections
        setupAppLifecycleMonitoring()
    }
    
    private func configureURLSession() {
        let config = URLSessionConfiguration.default
        
        // Configure for HTTP requests with shorter timeouts
        config.timeoutIntervalForRequest = 30.0      // 30 seconds
        config.timeoutIntervalForResource = 60.0     // 60 seconds total
        config.allowsCellularAccess = true
        config.waitsForConnectivity = false          // Don't wait indefinitely
        config.networkServiceType = .responsiveData
        
        // Disable caching for real-time connections
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        print("📡 INIT: URLSession configured for HTTP requests")
        
        self.urlSession = URLSession(configuration: config)
    }

    private func setupSocketManager() {
        guard let url = URL(string: baseURL) else {
            print("❌ SOCKET: Invalid base URL for SocketManager")
            return
        }
        
        // Configure the Socket.IO manager
        manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1), // Keep trying forever
            .reconnectWait(3),     // Wait 3 seconds before reconnecting
            .reconnectWaitMax(10), // Max wait 10 seconds
            .forceWebsockets(true),// Use WebSockets only, no long-polling fallback
            .secure(false)         // Set to true for https
        ])
        
        // Get the socket instance
        socket = manager?.defaultSocket
        
        // Setup event handlers
        setupSocketEventHandlers()

        print("📡 INIT: SocketManager configured for \(url)")
    }
    
    
    private func setupAppLifecycleMonitoring() {
        // Monitor when app becomes active to check connection
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let timestamp = Date().timeIntervalSince1970
                print("📱 APP LIFECYCLE: Did become active at \(timestamp)")
                print("📱 APP LIFECYCLE: Connection state: \(self.isConnected)")
                self.handleAppBecameActive()
            }
        }
        
        // Monitor when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let timestamp = Date().timeIntervalSince1970
                print("📱 APP LIFECYCLE: Did enter background at \(timestamp)")
                print("📱 APP LIFECYCLE: Connection state: \(self.isConnected)")
                self.handleAppEnteredBackground()
            }
        }
        
        // Monitor when app will resign active
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let timestamp = Date().timeIntervalSince1970
                print("📱 APP LIFECYCLE: Will resign active at \(timestamp)")
                print("📱 APP LIFECYCLE: Connection state: \(self.isConnected)")
            }
        }
        
        // Monitor when app will enter foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let timestamp = Date().timeIntervalSince1970
                print("📱 APP LIFECYCLE: Will enter foreground at \(timestamp)")
                print("📱 APP LIFECYCLE: Connection state: \(self.isConnected)")
            }
        }
    }
    
    private func handleAppBecameActive() {
        print("📱 App became active - checking connection")
        // The socket manager will automatically try to reconnect if disconnected
        if socket?.status == .notConnected {
            socket?.connect()
        }
    }
    
    private func handleAppEnteredBackground() {
        print("📱 App entered background - connection may be suspended")
        // Optionally disconnect or let the OS manage the connection
        // socket?.disconnect()
    }
    
    deinit {
        socket?.disconnect()
        manager = nil
        playerListTimer?.invalidate()
        playerListTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Socket Connection
    
    func connect(playerId: String) {
        guard let socket = socket else {
            print("❌ SOCKET: Socket not initialized")
            return
        }
        
        if socket.status == .connected {
            // If already connected, just send the player-connect event
            socket.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            return
        }
        connectionStatus = .connecting

        // The player ID is sent upon connection
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self = self else { return }
            self.connectionStatus = .connected
            self.isConnected = true
            
            
            // Emit player-connect event to associate player ID with socket ID
            self.socket?.emit("player-connect", with: [["playerId": playerId]], completion: nil)

            // Start periodic updates
            self.startPeriodicPlayerListFetch()
        }
        
        socket.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    private func setupSocketEventHandlers() {
        guard let socket = socket else { 
            print("❌ SOCKET SETUP: No socket available")
            return 
        }
        
        print("🔧 SOCKET SETUP: Setting up event handlers")

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.connectionStatus = .disconnected
            self?.isConnected = false
            self?.stopPeriodicPlayerListFetch()
        }
        
        socket.on(clientEvent: .error) { [weak self] data, _ in
            let error = data.first as? String ?? "Unknown error"
            print("❌ SOCKET: Connection error: \(error)")
            print("❌ SOCKET: Error data: \(data)")
            self?.connectionStatus = .error(error)
            self?.isConnected = false
            self?.stopPeriodicPlayerListFetch()
        }
        
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            print("🔄 SOCKET: Reconnected!")
            self?.connectionStatus = .connected
            self?.isConnected = true
            if let playerId = self?.currentPlayer?.id {
                self?.socket?.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            }
        }
        
        socket.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            if let attempt = data.first as? Int {
                print("🔄 SOCKET: Attempting to reconnect... (attempt \(attempt))")
                self?.connectionStatus = .connecting
            }
        }

        // --- Custom Event Handlers ---
        
        socket.on("welcome") { _, _ in
            print("🎉 SOCKET: Welcome message received")
        }
        
        socket.on("player-list-updated") { [weak self] data, _ in
            print("👥 SOCKET: Received 'player-list-updated'")
            self?.handlePlayerListUpdate(data: data)
        }
        
        socket.on("player-joined") { [weak self] data, _ in
            self?.handlePlayerListUpdate(data: data)
        }
        
        socket.on("player-left") { [weak self] _, _ in
            // For simplicity, we just refetch the whole list.
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchOnlinePlayers()
            }
        }
        
        socket.on("new-phrase") { [weak self] data, _ in
            self?.handleNewPhrase(data: data)
        }
        
        socket.on("phrase-completion-notification") { [weak self] data, _ in
            self?.handlePhraseCompletionNotification(data: data)
        }
        
    }

    private func handlePlayerListUpdate(data: [Any]) {
        guard let payload = data.first as? [String: Any],
              let playersData = payload["players"] else {
            print("❌ SOCKET: Invalid player list data format")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: playersData)
            let decoder = JSONDecoder()
            let players = try decoder.decode([Player].self, from: jsonData)
            
            DispatchQueue.main.async {
                self.onlinePlayers = players
                print("👥 SOCKET: Updated online players list with \(players.count) players.")
            }
        } catch {
            print("❌ SOCKET: Failed to decode player list: \(error.localizedDescription)")
        }
    }
    
    private func handleNewPhrase(data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            print("❌ SOCKET: No payload in data or not a dictionary")
            return
        }
        
        guard let phraseData = payload["phrase"] as? [String: Any] else {
            print("❌ SOCKET: No 'phrase' field in payload or not a dictionary")
            return
        }
        
        guard let senderName = payload["senderName"] as? String else {
            print("❌ SOCKET: No 'senderName' field in payload or not a string")
            return
        }
        
        
        do {
            // Add senderName to the phrase data for decoding
            var mutablePhraseData = phraseData
            mutablePhraseData["senderName"] = senderName
            
            
            let jsonData = try JSONSerialization.data(withJSONObject: mutablePhraseData)
            let decoder = JSONDecoder()
            let phrase = try decoder.decode(CustomPhrase.self, from: jsonData)
            
            
            DispatchQueue.main.async {
                // Store the latest received phrase for immediate preview
                self.lastReceivedPhrase = phrase
                self.hasNewPhrase = true
                
                // Trigger immediate notification
                self.justReceivedPhrase = phrase
            }
        } catch {
            print("❌ SOCKET: Failed to decode new phrase: \(error.localizedDescription)")
        }
    }
    
    private func handlePhraseCompletionNotification(data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            print("❌ SOCKET: Invalid phrase completion notification data format")
            return
        }
        
        guard let message = payload["message"] as? String else {
            print("❌ SOCKET: Missing required fields in phrase completion notification")
            return
        }
        
        print("🎉 NOTIFICATION: Received phrase completion notification - \(message)")
        
        // Trigger the notification on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Use the GameModel's messageTileSpawner to show the notification
            self.gameModel?.messageTileSpawner?.spawnMessageTile(message: message)
        }
    }
    
    // MARK: - HTTP API Methods
    
    func registerPlayer(name: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/players/register") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = RegistrationRequestBody(name: name)
            
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
                print("❌ REGISTER: Failed to register player. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
            // Decode the response to get the player object
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let playerData = jsonResponse["player"] {
                let playerDataJSON = try JSONSerialization.data(withJSONObject: playerData)
                let player = try JSONDecoder().decode(Player.self, from: playerDataJSON)
                
                self.currentPlayer = player
                
                // Now, connect to the socket and wait a bit for connection
                connect(playerId: player.id)
                
                // Give the socket time to connect before returning
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                return true
            }
            
            return false
            
        } catch {
            print("❌ REGISTER: Error registering player: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchOnlinePlayers() async {
        // Prevent concurrent requests
        if isFetchingPlayers { return }
        
        isFetchingPlayers = true
        defer { isFetchingPlayers = false }
        
        guard let url = URL(string: "\(baseURL)/api/players/online") else {
            print("❌ FETCH: Invalid URL for fetching players")
            return
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ FETCH: Failed to fetch players. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            
            // Decode the response
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let playersData = jsonResponse["players"] {
                let jsonData = try JSONSerialization.data(withJSONObject: playersData)
                let players = try JSONDecoder().decode([Player].self, from: jsonData)
                self.onlinePlayers = players
                self.lastPlayerListFetch = Date()
                print("👥 FETCH: Successfully fetched \(players.count) online players")
            }
        } catch {
            print("❌ FETCH: Error fetching online players: \(error.localizedDescription)")
        }
    }
    
    func sendPhrase(content: String, targetId: String, clue: String? = nil, language: String = "en") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/phrases") else {
            print("❌ PHRASE: Invalid URL for sending phrase")
            return false
        }
        
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player registered")
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var requestBody: [String: Any] = [
                "content": content,
                "senderId": currentPlayer.id,
                "targetId": targetId,
                "language": language
            ]
            
            // Add clue if provided (sent as "hint" to server for compatibility)
            if let clue = clue, !clue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                requestBody["hint"] = clue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                return true
            } else {
                print("❌ PHRASE: Failed to send phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
        } catch {
            print("❌ PHRASE: Error sending phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func createGlobalPhrase(content: String, hint: String, language: String = "en") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/phrases/create") else {
            print("❌ GLOBAL PHRASE: Invalid URL for creating global phrase")
            return false
        }
        
        guard let currentPlayer = currentPlayer else {
            print("❌ GLOBAL PHRASE: No current player registered")
            return false
        }
        
        print("🔍 GLOBAL PHRASE: Creating global phrase for player: \(currentPlayer.name) (ID: \(currentPlayer.id))")
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "content": content,
                "hint": hint,
                "senderId": currentPlayer.id,
                "targetIds": [], // Empty for global phrases
                "isGlobal": true,
                "language": language,
                "phraseType": "custom"
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                print("✅ GLOBAL PHRASE: Successfully created global phrase")
                return true
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ GLOBAL PHRASE: Failed to create global phrase. Status code: \(statusCode)")
                print("❌ GLOBAL PHRASE: Response: \(responseBody)")
                return false
            }
            
        } catch {
            print("❌ GLOBAL PHRASE: Error creating global phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func createEnhancedPhrase(content: String, hint: String, targetIds: [String], isGlobal: Bool, language: String = "en") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/phrases/create") else {
            print("❌ ENHANCED PHRASE: Invalid URL for creating enhanced phrase")
            return false
        }
        
        guard let currentPlayer = currentPlayer else {
            print("❌ ENHANCED PHRASE: No current player registered")
            return false
        }
        
        print("🔍 ENHANCED PHRASE: Creating phrase for player: \(currentPlayer.name) (ID: \(currentPlayer.id))")
        print("🔍 ENHANCED PHRASE: Global: \(isGlobal), Targets: \(targetIds.count), Language: \(language)")
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "content": content,
                "hint": hint,
                "senderId": currentPlayer.id,
                "targetIds": targetIds,
                "isGlobal": isGlobal,
                "language": language,
                "phraseType": "custom"
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                print("✅ ENHANCED PHRASE: Successfully created enhanced phrase")
                return true
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ ENHANCED PHRASE: Failed to create enhanced phrase. Status code: \(statusCode)")
                print("❌ ENHANCED PHRASE: Response: \(responseBody)")
                return false
            }
            
        } catch {
            print("❌ ENHANCED PHRASE: Error creating enhanced phrase: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchPhrasesForCurrentPlayer() async -> [CustomPhrase] {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player registered")
            return []
        }
        
        guard let url = URL(string: "\(baseURL)/api/phrases/for/\(currentPlayer.id)") else {
            print("❌ PHRASE: Invalid URL for fetching phrases")
            return []
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ PHRASE: Failed to fetch phrases. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let phrasesData = jsonResponse["phrases"] {
                let jsonData = try JSONSerialization.data(withJSONObject: phrasesData)
                let phrases = try JSONDecoder().decode([CustomPhrase].self, from: jsonData)
                return phrases
            }
            
            return []
        } catch {
            print("❌ PHRASE: Error fetching phrases: \(error.localizedDescription)")
            return []
        }
    }
    
    func consumePhrase(phraseId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/consume") else {
            print("❌ PHRASE: Invalid URL for consuming phrase")
            return false
        }
        
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
    
    func skipPhrase(phraseId: String) async -> Bool {
        guard let currentPlayer = currentPlayer else {
            print("❌ PHRASE: No current player to skip phrase")
            return false
        }
        
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/skip") else {
            print("❌ PHRASE: Invalid URL for skipping phrase")
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
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
    
    // MARK: - Hint System API Methods (Phase 4.8)
    
    func getPhrasePreview(phraseId: String) async -> PhrasePreview? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player for phrase preview")
            return nil
        }
        
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/preview?playerId=\(currentPlayer.id)") else {
            print("❌ HINT: Invalid URL for phrase preview")
            return nil
        }
        
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
    
    func useHint(phraseId: String, level: Int) async -> HintResponse? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player to use hint")
            return nil
        }
        
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/hint/\(level)") else {
            print("❌ HINT: Invalid URL for using hint")
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["playerId": currentPlayer.id]
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ HINT: Failed to use hint. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let hintResponse = try JSONDecoder().decode(HintResponse.self, from: data)
            print("🔍 HINT: Successfully used level \(level) hint: \(hintResponse.hint.content)")
            return hintResponse
            
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
        
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/hints/status?playerId=\(currentPlayer.id)") else {
            print("❌ HINT: Invalid URL for hint status")
            return nil
        }
        
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
    
    func completePhrase(phraseId: String, completionTime: Int = 0) async -> CompletionResult? {
        guard let currentPlayer = currentPlayer else {
            print("❌ HINT: No current player to complete phrase")
            return nil
        }
        
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/complete") else {
            print("❌ HINT: Invalid URL for completing phrase")
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "playerId": currentPlayer.id,
                "completionTime": completionTime
            ] as [String : Any]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ HINT: Failed to complete phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let completionResult = try JSONDecoder().decode(CompletionResult.self, from: data)
            print("✅ HINT: Successfully completed phrase with score \(completionResult.completion.finalScore)")
            return completionResult
            
        } catch {
            print("❌ HINT: Error completing phrase: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Periodic Updates
    
    func startPeriodicPlayerListFetch() {
        stopPeriodicPlayerListFetch() // Ensure no multiple timers are running
        
        // Fetch immediately
        Task {
            await fetchOnlinePlayers()
        }
        
        playerListTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchOnlinePlayers()
            }
        }
        print("⏰ TIMER: Started periodic player list fetch (every 15s)")
    }
    
    func stopPeriodicPlayerListFetch() {
        playerListTimer?.invalidate()
        playerListTimer = nil
        print("⏰ TIMER: Stopped periodic player list fetch")
    }
    
    // MARK: - Lobby & Scoring API Methods (Phase 4.9)
    
    func getPlayerStats(playerId: String) async throws -> PlayerStats {
        guard let url = URL(string: "\(baseURL)/api/scores/player/\(playerId)") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ STATS: Failed to get player stats. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let scoresData = jsonResponse["scores"] as? [String: Any] {
                
                let dailyScore = scoresData["dailyScore"] as? Int ?? 0
                let dailyRank = scoresData["dailyRank"] as? Int ?? 0
                let weeklyScore = scoresData["weeklyScore"] as? Int ?? 0
                let weeklyRank = scoresData["weeklyRank"] as? Int ?? 0
                let totalScore = scoresData["totalScore"] as? Int ?? 0
                let totalRank = scoresData["totalRank"] as? Int ?? 0
                let totalPhrases = scoresData["totalPhrases"] as? Int ?? 0
                
                let stats = PlayerStats(
                    dailyScore: dailyScore,
                    dailyRank: dailyRank,
                    weeklyScore: weeklyScore,
                    weeklyRank: weeklyRank,
                    totalScore: totalScore,
                    totalRank: totalRank,
                    totalPhrases: totalPhrases
                )
                
                print("📊 STATS: Successfully got player stats: \(totalScore) total points")
                return stats
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ STATS: Error getting player stats: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    func getLeaderboard(period: String, limit: Int = 10) async throws -> [LeaderboardEntry] {
        guard let url = URL(string: "\(baseURL)/api/leaderboards/\(period)?limit=\(limit)") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ LEADERBOARD: Failed to get leaderboard. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let leaderboardData = jsonResponse["leaderboard"] as? [[String: Any]] {
                
                let entries = leaderboardData.compactMap { entry -> LeaderboardEntry? in
                    guard let rank = entry["rank"] as? Int,
                          let playerName = entry["playerName"] as? String,
                          let totalScore = entry["totalScore"] as? Int,
                          let phrasesCompleted = entry["phrasesCompleted"] as? Int else {
                        return nil
                    }
                    
                    return LeaderboardEntry(
                        rank: rank,
                        playerName: playerName,
                        totalScore: totalScore,
                        phrasesCompleted: phrasesCompleted
                    )
                }
                
                print("🏆 LEADERBOARD: Successfully got \(entries.count) leaderboard entries for \(period)")
                return entries
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ LEADERBOARD: Error getting leaderboard: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    func getOnlinePlayersCount() async throws -> Int {
        guard let url = URL(string: "\(baseURL)/api/players/online") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ ONLINE COUNT: Failed to get online players count. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let playersData = jsonResponse["players"] as? [[String: Any]] {
                
                let count = playersData.count
                print("👥 ONLINE COUNT: Successfully got online players count: \(count)")
                return count
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ ONLINE COUNT: Error getting online players count: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Legacy API for compatibility
    
    func testConnection() async -> Result<Bool, NetworkError> {
        guard let url = URL(string: "\(baseURL)/api/status") else {
            print("❌ TEST: Invalid URL: \(baseURL)")
            return .failure(.invalidURL)
        }
        
        print("🔍 TEST: Testing connection to \(baseURL)")
        
        do {
            // Add timeout to prevent hanging
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0 // 10 second timeout
            
            let (data, response) = try await urlSession.data(for: request)
            
            print("🔍 TEST: Got response, status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ TEST: Server returned status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return .failure(.serverOffline)
            }
            
            // Parse the response to validate it's our server
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = jsonResponse["status"] as? String,
               status == "online" {
                print("✅ TEST: Connection successful")
                return .success(true)
            }
            
            print("❌ TEST: Invalid response format")
            return .failure(.invalidResponse)
        } catch {
            print("❌ TEST: Connection failed with error: \(error.localizedDescription)")
            return .failure(.connectionFailed)
        }
    }
    
    func connect() {
        // Legacy method that creates a basic connection without player ID
        print("📡 LEGACY: Basic connect() called - setting up socket")
        setupSocketManager()
    }
    
    func sendManualPing() {
        guard let socket = socket else {
            print("❌ Cannot send manual ping - no socket")
            return
        }
        print("🔧 MANUAL PING TEST: Sending ping via SocketIO")
        // SocketIO doesn't have a manual ping method, so we send a custom message
        socket.emit("ping", completion: nil)
    }
    
    // MARK: - Difficulty Analysis API Method
    
    func analyzeDifficulty(phrase: String, language: String = "en") async -> DifficultyAnalysis? {
        guard let url = URL(string: "\(baseURL)/api/phrases/analyze-difficulty") else {
            print("❌ DIFFICULTY: Invalid URL for analyzing difficulty")
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "phrase": phrase.trimmingCharacters(in: .whitespacesAndNewlines),
                "language": language
            ]
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ DIFFICULTY: Failed to analyze difficulty. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let analysis = try JSONDecoder().decode(DifficultyAnalysis.self, from: data)
            print("📊 DIFFICULTY: Analyzed '\(phrase)' -> Score: \(analysis.score) (\(analysis.difficulty))")
            return analysis
            
        } catch {
            print("❌ DIFFICULTY: Error analyzing difficulty: \(error.localizedDescription)")
            return nil
        }
    }
    
}

// MARK: - Difficulty Analysis Data Models

public struct DifficultyAnalysis: Codable {
    let phrase: String
    let language: String
    let score: Double
    let difficulty: String
    let timestamp: String
}

// MARK: - Client-Side Difficulty Scoring (Reads Shared Configuration)

extension NetworkManager {
    
    /// Client-side difficulty scorer for real-time UI feedback during phrase creation.
    /// Reads from the shared JSON configuration to ensure identical algorithm with server.
    static func analyzeDifficultyClientSide(phrase: String, language: String = "en") -> DifficultyAnalysis {
        guard let config = SharedDifficultyConfig.load() else {
            return DifficultyAnalysis(
                phrase: phrase,
                language: language,
                score: 1.0,
                difficulty: "Very Easy",
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        return config.calculateDifficulty(phrase: phrase, language: language)
    }
}

// MARK: - Shared Configuration Reader

private struct SharedDifficultyConfig: Codable {
    let version: String
    let lastUpdated: String
    let languages: Languages
    let letterFrequencies: [String: [String: Double]]
    let maxFrequencies: [String: Double]
    let difficultyThresholds: DifficultyThresholds
    let difficultyLabels: DifficultyLabels
    let algorithmParameters: AlgorithmParameters
    let textNormalization: [String: TextNormalization]
    let languageDetection: LanguageDetection
    
    struct Languages: Codable {
        let english: String
        let swedish: String
    }
    
    struct DifficultyThresholds: Codable {
        let veryEasy: Double
        let easy: Double
        let medium: Double
        let hard: Double
    }
    
    struct DifficultyLabels: Codable {
        let veryEasy: String
        let easy: String
        let medium: String
        let hard: String
        let veryHard: String
    }
    
    struct AlgorithmParameters: Codable {
        let wordCount: WordCountParams
        let letterCount: LetterCountParams
        let commonality: CommonalityParams
        let letterRepetition: LetterRepetitionParams
        let minimumScore: Double
        
        struct WordCountParams: Codable {
            let exponent: Double
            let multiplier: Double
        }
        
        struct LetterCountParams: Codable {
            let exponent: Double
            let multiplier: Double
        }
        
        struct CommonalityParams: Codable {
            let multiplier: Double
            let shortPhraseThreshold: Int
            let shortPhraseDampening: Double
        }
        
        struct LetterRepetitionParams: Codable {
            let multiplier: Double
            let description: String
        }
    }
    
    struct TextNormalization: Codable {
        let regex: String
        let description: String
    }
    
    struct LanguageDetection: Codable {
        let swedishCharacters: String
        let defaultLanguage: String
    }
    
    static func load() -> SharedDifficultyConfig? {
        guard let path = Bundle.main.path(forResource: "difficulty-algorithm-config", ofType: "json"),
              let data = NSData(contentsOfFile: path) as Data? else {
            print("❌ Could not find difficulty-algorithm-config.json in app bundle")
            return nil
        }
        
        do {
            let config = try JSONDecoder().decode(SharedDifficultyConfig.self, from: data)
            print("✅ Loaded shared difficulty config version \(config.version)")
            return config
        } catch {
            print("❌ Failed to decode shared config: \(error)")
            return nil
        }
    }
    
    func calculateDifficulty(phrase: String, language: String) -> DifficultyAnalysis {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DifficultyAnalysis(
                phrase: phrase,
                language: language,
                score: algorithmParameters.minimumScore,
                difficulty: difficultyLabels.veryEasy,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        let detectedLanguage = language.isEmpty ? detectLanguage(phrase) : language
        let normalizedText = normalize(phrase: phrase, language: detectedLanguage)
        let wordCount = countWords(phrase)
        let letterCount = normalizedText.count
        
        guard letterCount > 0 else {
            return DifficultyAnalysis(
                phrase: phrase,
                language: detectedLanguage,
                score: algorithmParameters.minimumScore,
                difficulty: difficultyLabels.veryEasy,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        let score = calculateScore(
            normalizedText: normalizedText,
            wordCount: wordCount,
            letterCount: letterCount,
            language: detectedLanguage
        )
        
        return DifficultyAnalysis(
            phrase: phrase,
            language: detectedLanguage,
            score: score,
            difficulty: getDifficultyLabel(for: score),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    private func normalize(phrase: String, language: String) -> String {
        guard !phrase.isEmpty else { return "" }
        
        let text = phrase.lowercased()
        let normalization = textNormalization[language] ?? textNormalization[languages.english]!
        
        return text.replacingOccurrences(of: normalization.regex, with: "", options: .regularExpression)
    }
    
    private func countWords(_ phrase: String) -> Int {
        return phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private func detectLanguage(_ phrase: String) -> String {
        guard !phrase.isEmpty else { return languageDetection.defaultLanguage }
        
        let text = phrase.lowercased()
        
        if text.range(of: languageDetection.swedishCharacters, options: .regularExpression) != nil {
            return languages.swedish
        }
        
        return languageDetection.defaultLanguage
    }
    
    private func calculateScore(normalizedText: String, wordCount: Int, letterCount: Int, language: String) -> Double {
        let frequencies = letterFrequencies[language] ?? letterFrequencies[languages.english]!
        let maxFrequency = maxFrequencies[language] ?? maxFrequencies[languages.english]!
        
        // 1. Word Count Factor
        let wordCountFactor = pow(
            Double(max(0, wordCount - 1)),
            algorithmParameters.wordCount.exponent
        ) * algorithmParameters.wordCount.multiplier
        
        // 2. Letter Count Factor
        let letterCountFactor = pow(
            Double(letterCount),
            algorithmParameters.letterCount.exponent
        ) * algorithmParameters.letterCount.multiplier
        
        // 3. Letter Commonality Factor
        var totalFrequency = 0.0
        for char in normalizedText {
            totalFrequency += frequencies[String(char)] ?? 0.0
        }
        let averageFrequency = totalFrequency / Double(letterCount)
        var commonalityFactor = (averageFrequency / maxFrequency) * algorithmParameters.commonality.multiplier
        
        // Dampen commonality for very short phrases
        if letterCount <= algorithmParameters.commonality.shortPhraseThreshold {
            commonalityFactor *= algorithmParameters.commonality.shortPhraseDampening
        }
        
        // 4. Letter Repetition Factor
        let uniqueLetters = Set(normalizedText).count
        let repetitionRatio = Double(letterCount - uniqueLetters) / Double(letterCount)
        let repetitionFactor = repetitionRatio * algorithmParameters.letterRepetition.multiplier
        
        // Combine factors and clamp the score
        let rawScore = wordCountFactor + letterCountFactor + commonalityFactor + repetitionFactor
        return round(max(algorithmParameters.minimumScore, rawScore))
    }
    
    private func getDifficultyLabel(for score: Double) -> String {
        switch score {
        case ...difficultyThresholds.veryEasy:
            return difficultyLabels.veryEasy
        case ...difficultyThresholds.easy:
            return difficultyLabels.easy
        case ...difficultyThresholds.medium:
            return difficultyLabels.medium
        case ...difficultyThresholds.hard:
            return difficultyLabels.hard
        default:
            return difficultyLabels.veryHard
        }
    }
}

// MARK: - Lobby Data Models

public struct PlayerStats: Codable {
    let dailyScore: Int
    let dailyRank: Int
    let weeklyScore: Int
    let weeklyRank: Int
    let totalScore: Int
    let totalRank: Int
    let totalPhrases: Int
}

public struct LeaderboardEntry: Codable {
    let rank: Int
    let playerName: String
    let totalScore: Int
    let phrasesCompleted: Int
}

// MARK: - Helper extensions (can be in a separate file)

extension DateFormatter {
    static let iso8601Full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}