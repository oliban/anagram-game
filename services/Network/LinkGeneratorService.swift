//
//  LinkGeneratorService.swift
//  Anagram Game
//
//  Service for managing contribution link generation and health monitoring
//

import Foundation

class LinkGeneratorService {
    private let baseURL = AppConfig.contributionBaseURL
    private var urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Health Check
    
    func performHealthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/status") else {
            DebugLogger.shared.error("Invalid link generator service URL")
            return false
        }
        
        do {
            let (_, response) = try await urlSession.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DebugLogger.shared.network("Link generator service is healthy")
                return true
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                DebugLogger.shared.error("Link generator service returned status code: \(statusCode)")
                return false
            }
            
        } catch {
            DebugLogger.shared.error("Link generator service health check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Link Generation
    
    func generateContributionLink(playerId: String, expirationHours: Int = 24, maxUses: Int = 3) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/contribution/request") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "playerId": playerId,
            "expirationHours": expirationHours,
            "maxUses": maxUses
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        DebugLogger.shared.network("Generating contribution link for player: \(playerId)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            DebugLogger.shared.error("Failed to generate contribution link. Status: \(statusCode)")
            throw NetworkError.serverOffline
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let linkData = json["link"] as? [String: Any],
              let shareableUrl = linkData["shareableUrl"] as? String else {
            DebugLogger.shared.error("Invalid response format from link generator")
            throw NetworkError.invalidResponse
        }
        
        DebugLogger.shared.network("Successfully generated contribution link")
        return shareableUrl
    }
}