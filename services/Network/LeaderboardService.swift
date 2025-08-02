//
//  LeaderboardService.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Handles leaderboard data and legend players
//

import Foundation

class LeaderboardService {
    @Published var dailyLeaderboard: [LeaderboardEntry] = []
    @Published var weeklyLeaderboard: [LeaderboardEntry] = []
    @Published var allTimeLeaderboard: [LeaderboardEntry] = []
    @Published var legendPlayers: [LegendPlayer] = []
    
    private let baseURL = AppConfig.baseURL
    private var urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Leaderboard Data
    
    func fetchDailyLeaderboard() async throws -> [LeaderboardEntry] {
        return try await fetchLeaderboard(type: "daily")
    }
    
    func fetchWeeklyLeaderboard() async throws -> [LeaderboardEntry] {
        return try await fetchLeaderboard(type: "weekly")
    }
    
    func fetchAllTimeLeaderboard() async throws -> [LeaderboardEntry] {
        return try await fetchLeaderboard(type: "total")
    }
    
    private func fetchLeaderboard(type: String) async throws -> [LeaderboardEntry] {
        guard let url = URL(string: "\(baseURL)/api/leaderboard/\(type)") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ LEADERBOARD: Failed to fetch \(type) leaderboard. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let leaderboardData = json["leaderboard"] as? [[String: Any]] {
                
                let entries = leaderboardData.compactMap { entryDict -> LeaderboardEntry? in
                    guard let rank = entryDict["rank"] as? Int,
                          let playerName = entryDict["playerName"] as? String,
                          let totalScore = entryDict["totalScore"] as? Int,
                          let phrasesCompleted = entryDict["phrasesCompleted"] as? Int else {
                        return nil
                    }
                    
                    return LeaderboardEntry(
                        rank: rank,
                        playerName: playerName,
                        totalScore: totalScore,
                        phrasesCompleted: phrasesCompleted
                    )
                }
                
                await MainActor.run {
                    switch type {
                    case "daily":
                        self.dailyLeaderboard = entries
                    case "weekly":
                        self.weeklyLeaderboard = entries
                    case "total":
                        self.allTimeLeaderboard = entries
                    default:
                        break
                    }
                }
                
                print("✅ LEADERBOARD: Fetched \(type) leaderboard with \(entries.count) entries")
                return entries
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ LEADERBOARD: Error fetching \(type) leaderboard: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Legend Players
    
    func fetchLegendPlayers() async throws -> LegendPlayersResponse {
        guard let url = URL(string: "\(baseURL)/api/players/legends") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ LEGEND: Failed to fetch legend players. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            let legendResponse = try JSONDecoder().decode(LegendPlayersResponse.self, from: data)
            
            await MainActor.run {
                self.legendPlayers = legendResponse.players
            }
            
            print("✅ LEGEND: Fetched \(legendResponse.players.count) legend players")
            return legendResponse
            
        } catch {
            print("❌ LEGEND: Error fetching legend players: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    func isLegendPlayer(skillLevel: Int, minimumLevel: Int) -> Bool {
        return skillLevel >= minimumLevel
    }
    
    // MARK: - Player Rankings
    
    func getPlayerRanking(playerId: String, in leaderboardType: String) async throws -> Int? {
        guard let url = URL(string: "\(baseURL)/api/leaderboard/\(leaderboardType)/player/\(playerId)") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ RANKING: Failed to get player ranking. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let ranking = json["rank"] as? Int {
                
                print("✅ RANKING: Player \(playerId) rank in \(leaderboardType): \(ranking)")
                return ranking
            }
            
            return nil
            
        } catch {
            print("❌ RANKING: Error getting player ranking: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
}