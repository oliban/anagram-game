import Foundation
import Network
import UIKit
import SocketIO

// Player model matching server-side structure
struct Player: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let connectedAt: Date
    let isActive: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id, name, connectedAt, isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        
        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .connectedAt)
        let formatter = ISO8601DateFormatter()
        connectedAt = formatter.date(from: dateString) ?? Date()
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
    
    private enum CodingKeys: String, CodingKey {
        case id, content, senderId, targetId, createdAt, isConsumed, senderName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decode(String.self, forKey: .senderId)
        targetId = try container.decode(String.self, forKey: .targetId)
        isConsumed = try container.decode(Bool.self, forKey: .isConsumed)
        senderName = try container.decode(String.self, forKey: .senderName)
        
        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        createdAt = formatter.date(from: dateString) ?? Date()
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
    @Published var pendingPhrases: [CustomPhrase] = []
    @Published var lastReceivedPhrase: CustomPhrase? = nil
    
    private let baseURL = "http://192.168.1.133:3000"
    private var urlSession: URLSession
    private var playerListTimer: Timer?
    private var connectionMonitorTimer: Timer?
    private var lastPlayerListFetch: Date = Date.distantPast
    private var isFetchingPlayers: Bool = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
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
        
        print("🔧 SOCKET SETUP: ✅ All event handlers registered")
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
            print("❌ SOCKET: Data: \(data)")
            return
        }
        
        
        guard let phraseData = payload["phrase"] as? [String: Any] else {
            print("❌ SOCKET: No 'phrase' field in payload or not a dictionary")
            print("❌ SOCKET: Payload: \(payload)")
            return
        }
        
        guard let senderName = payload["senderName"] as? String else {
            print("❌ SOCKET: No 'senderName' field in payload or not a string")
            print("❌ SOCKET: Payload: \(payload)")
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
                
                // Force update the published array
                var updatedPhrases = self.pendingPhrases
                updatedPhrases.append(phrase)
                self.pendingPhrases = updatedPhrases
                
                self.lastReceivedPhrase = phrase
                
                print("🎯 NEXT WORD PREVIEW: Your next game will be: '\(phrase.content)' (when you complete current game)")
            }
        } catch {
            print("❌ SOCKET: Failed to decode new phrase: \(error.localizedDescription)")
            print("❌ SOCKET: Error details: \(error)")
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
    
    func sendPhrase(content: String, targetId: String) async -> Bool {
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
            
            let requestBody: [String: Any] = [
                "content": content,
                "senderId": currentPlayer.id,
                "targetId": targetId
            ]
            
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
}

// MARK: - Helper extensions (can be in a separate file)

extension DateFormatter {
    static let iso8601Full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}