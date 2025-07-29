//
//  PlayerService.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Handles player registration, online players, and statistics
//

import Foundation

class PlayerService: PlayerServiceDelegate {
    @Published var currentPlayer: Player? = nil
    @Published var onlinePlayers: [Player] = []
    
    private let baseURL = AppConfig.baseURL
    private var urlSession: URLSession
    private var playerListTimer: Timer?
    private var lastPlayerListFetch: Date = Date.distantPast
    private var isFetchingPlayers: Bool = false
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Player Registration
    
    func registerPlayer(name: String) async -> RegistrationResult {
        guard let url = URL(string: "\(baseURL)/api/players/register") else {
            return .failure(message: "Invalid server URL")
        }
        
        let deviceId = DeviceManager.shared.getDeviceId()
        let requestBody = RegistrationRequestBody(name: name, deviceId: deviceId)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            print("🔐 REGISTER: Attempting registration for '\(name)' with device ID: \(deviceId)")
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(message: "Invalid response from server")
            }
            
            print("🔐 REGISTER: Response status: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200, 201:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let playerData = json["player"] as? [String: Any],
                   let playerId = playerData["id"] as? String,
                   let playerName = playerData["name"] as? String {
                    
                    let player = Player(
                        id: playerId,
                        name: playerName, 
                        lastSeen: Date(),
                        isActive: true,
                        phrasesCompleted: playerData["phrasesCompleted"] as? Int ?? 0
                    )
                    
                    await MainActor.run {
                        self.currentPlayer = player
                    }
                    
                    print("✅ REGISTER: Success! Player ID: \(playerId)")
                    return .success
                } else {
                    return .failure(message: "Invalid player data received")
                }
                
            case 409:
                // Name conflict - extract suggestions
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let suggestions = json["suggestions"] as? [String] {
                    print("⚠️ REGISTER: Name conflict. Suggestions: \(suggestions)")
                    return .nameConflict(suggestions: suggestions)
                } else {
                    return .nameConflict(suggestions: [])
                }
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ REGISTER: Failed with status \(httpResponse.statusCode): \(errorMessage)")
                return .failure(message: "Registration failed: \(errorMessage)")
            }
            
        } catch {
            print("❌ REGISTER: Network error: \(error.localizedDescription)")
            return .failure(message: "Network error: \(error.localizedDescription)")
        }
    }
    
    func registerPlayerBool(name: String) async -> Bool {
        let result = await registerPlayer(name: name)
        switch result {
        case .success:
            return true
        case .nameConflict, .failure:
            return false
        }
    }
    
    // MARK: - Online Players
    
    func fetchOnlinePlayers() async {
        guard !isFetchingPlayers else {
            print("⏭️ PLAYERS: Skipping fetch - already in progress")
            return
        }
        
        isFetchingPlayers = true
        defer { isFetchingPlayers = false }
        
        let now = Date()
        if now.timeIntervalSince(lastPlayerListFetch) < 2.0 {
            print("⏭️ PLAYERS: Skipping fetch - too soon since last fetch")
            return
        }
        
        lastPlayerListFetch = now
        
        guard let url = URL(string: "\(baseURL)/api/players/online") else {
            print("❌ PLAYERS: Invalid URL")
            return
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ PLAYERS: Failed to fetch. Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let playersArray = json["players"] as? [[String: Any]] {
                
                let players = playersArray.compactMap { playerDict -> Player in
                    // Create Player from dictionary manually since we need custom date parsing
                    guard let id = playerDict["id"] as? String,
                          let name = playerDict["name"] as? String else {
                        return Player(id: "", name: "", lastSeen: Date(), isActive: false, phrasesCompleted: 0)
                    }
                    
                    let isActive = playerDict["isActive"] as? Bool ?? false
                    let phrasesCompleted = playerDict["phrasesCompleted"] as? Int ?? 0
                    
                    // Handle date parsing
                    let lastSeen: Date
                    if let lastSeenString = playerDict["lastSeen"] as? String {
                        let formatter = ISO8601DateFormatter()
                        lastSeen = formatter.date(from: lastSeenString) ?? Date()
                    } else {
                        lastSeen = Date()
                    }
                    
                    return Player(id: id, name: name, lastSeen: lastSeen, isActive: isActive, phrasesCompleted: phrasesCompleted)
                }.filter { !$0.id.isEmpty }
                
                await MainActor.run {
                    self.onlinePlayers = players
                }
                
                print("👥 PLAYERS: Updated list - \(players.count) online")
            }
            
        } catch {
            print("❌ PLAYERS: Error fetching online players: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Player Statistics
    
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
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let scoresData = json["scores"] as? [String: Any] {
                
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
                
                print("📊 STATS: Retrieved stats for player \(playerId)")
                return stats
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ STATS: Error getting player stats: \(error.localizedDescription)")
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
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let players = json["players"] as? [[String: Any]] {
                return players.count
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ ONLINE COUNT: Error getting online players count: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Periodic Updates
    
    func startPeriodicPlayerListFetch() {
        stopPeriodicPlayerListFetch() // Ensure no duplicate timers
        
        playerListTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.playerListRefreshInterval, repeats: true) { _ in
            Task {
                await self.fetchOnlinePlayers()
            }
        }
        
        print("⏰ TIMER: Started periodic player list fetch (\(AppConfig.playerListRefreshInterval)s interval)")
    }
    
    func stopPeriodicPlayerListFetch() {
        playerListTimer?.invalidate()
        playerListTimer = nil
        print("⏰ TIMER: Stopped periodic player list fetch")
    }
    
    // MARK: - Socket Event Handling
    
    func handlePlayerListUpdate(data: [Any]) {
        print("📨 PLAYER SERVICE: handlePlayerListUpdate called with data: \(data)")
        
        // Handle the new format: data[0] is an object with "players" array and "timestamp"
        guard let updateData = data.first as? [String: Any],
              let playersData = updateData["players"] as? [[String: Any]] else {
            print("❌ SOCKET: Invalid players data format. Expected {players: [...], timestamp: ...}")
            print("❌ SOCKET: Raw data: \(data)")
            return
        }
        
        print("👥 SOCKET: Received player list update with \(playersData.count) players")
        
        let players = playersData.compactMap { playerDict -> Player in
            guard let id = playerDict["id"] as? String,
                  let name = playerDict["name"] as? String else {
                return Player(id: "", name: "", lastSeen: Date(), isActive: false, phrasesCompleted: 0)
            }
            
            let isActive = playerDict["isActive"] as? Bool ?? false
            let phrasesCompleted = playerDict["phrasesCompleted"] as? Int ?? 0
            
            let lastSeen: Date
            if let lastSeenString = playerDict["lastSeen"] as? String {
                let formatter = ISO8601DateFormatter()
                lastSeen = formatter.date(from: lastSeenString) ?? Date()
            } else {
                lastSeen = Date()
            }
            
            return Player(id: id, name: name, lastSeen: lastSeen, isActive: isActive, phrasesCompleted: phrasesCompleted)
        }.filter { !$0.id.isEmpty }
        
        DispatchQueue.main.async {
            self.onlinePlayers = players
        }
    }
}

// Helper struct for registration requests
private struct RegistrationRequestBody: Encodable {
    let name: String
    let deviceId: String
}