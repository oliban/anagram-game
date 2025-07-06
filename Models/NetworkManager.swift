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
        let config = URLSessionConfiguration.default
        
        // Configure for long-lived WebSocket connections
        config.timeoutIntervalForRequest = 60.0      // Increased from 10s
        config.timeoutIntervalForResource = 0        // No resource timeout (infinite)
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.networkServiceType = .responsiveData
        
        // Disable caching for real-time connections
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        print("📡 INIT: URLSession configured for HTTP requests")
        
        self.urlSession = URLSession(configuration: config)

        // Initialize Socket.IO manager
        setupSocketManager()
        
        // Monitor app lifecycle to maintain connections
        setupAppLifecycleMonitoring()
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
            print("🔌 SOCKET: Already connected.")
            return
        }

        print("🔌 SOCKET: Attempting to connect...")
        connectionStatus = .connecting

        // The player ID is sent upon connection
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self = self else { return }
            print("🔌 SOCKET: Connected successfully!")
            self.connectionStatus = .connected
            self.isConnected = true
            
            // Emit player-connect event to associate player ID with socket ID
            self.socket?.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            print("👤 SOCKET: Sent 'player-connect' for player ID: \(playerId)")

            // Start periodic updates
            self.startPeriodicPlayerListFetch()
        }
        
        socket.connect()
    }

    func disconnect() {
        print("🔌 SOCKET: Disconnecting...")
        socket?.disconnect()
    }

    private func setupSocketEventHandlers() {
        guard let socket = socket else { return }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            print("🔌 SOCKET: Disconnected.")
            self?.connectionStatus = .disconnected
            self?.isConnected = false
            self?.stopPeriodicPlayerListFetch()
        }
        
        socket.on(clientEvent: .error) { [weak self] data, _ in
            let error = data.first as? String ?? "Unknown error"
            print("❌ SOCKET: Connection error: \(error)")
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
                print("👤 SOCKET: Sent 'player-connect' on reconnect for player ID: \(playerId)")
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
            print("👤 SOCKET: Received 'player-joined'")
            self?.handlePlayerListUpdate(data: data)
        }
        
        socket.on("player-left") { [weak self] _, _ in
            print("👤 SOCKET: Received 'player-left'")
            // For simplicity, we just refetch the whole list.
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchOnlinePlayers()
            }
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
                print("👤 REGISTER: Player registered successfully: \(player.name) (\(player.id))")
                
                // Now, connect to the socket
                connect(playerId: player.id)
                
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
            return .failure(.invalidURL)
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .failure(.serverOffline)
            }
            
            // Parse the response to validate it's our server
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = jsonResponse["status"] as? String,
               status == "online" {
                return .success(true)
            }
            
            return .failure(.invalidResponse)
        } catch {
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