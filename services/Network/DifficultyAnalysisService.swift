//
//  DifficultyAnalysisService.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Handles difficulty analysis and server configuration
//

import Foundation

class DifficultyAnalysisService {
    private let baseURL = AppConfig.baseURL
    private var urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Server Configuration
    
    func fetchServerConfig() async throws -> ServerConfig {
        // Eliminate redundant /api/status call during startup
        // Server config fetching is not critical for app functionality
        // and this call is already wrapped in try? in ContentView
        print("⚠️ CONFIG: Server config fetch disabled to reduce startup calls")
        throw NetworkError.connectionFailed
    }
    
    // MARK: - Difficulty Analysis
    
    func analyzePhrasesDifficulty(phrases: [String], language: String = "en") async throws -> [DifficultyAnalysis] {
        guard let url = URL(string: "\(baseURL)/api/phrases/analyze-difficulty") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "phrases": phrases,
            "language": language
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ ANALYSIS: Failed to analyze phrases difficulty. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let analysisData = json["analysis"] as? [[String: Any]] {
                
                let analyses = analysisData.compactMap { analysisDict -> DifficultyAnalysis? in
                    guard let phrase = analysisDict["phrase"] as? String,
                          let language = analysisDict["language"] as? String,
                          let score = analysisDict["score"] as? Double,
                          let difficulty = analysisDict["difficulty"] as? String,
                          let timestamp = analysisDict["timestamp"] as? String else {
                        return nil
                    }
                    
                    return DifficultyAnalysis(
                        phrase: phrase,
                        language: language,
                        score: score,
                        difficulty: difficulty,
                        timestamp: timestamp
                    )
                }
                
                print("✅ ANALYSIS: Analyzed \(analyses.count) phrases for difficulty")
                return analyses
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ ANALYSIS: Error analyzing phrases difficulty: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    func analyzeSinglePhraseDifficulty(phrase: String, language: String = "en") async throws -> DifficultyAnalysis {
        let analyses = try await analyzePhrasesDifficulty(phrases: [phrase], language: language)
        
        guard let analysis = analyses.first else {
            throw NetworkError.invalidResponse
        }
        
        return analysis
    }
    
    // MARK: - Health Check
    
    func performHealthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/status") else {
            print("❌ HEALTH: Invalid server URL")
            return false
        }
        
        do {
            let (_, response) = try await urlSession.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ HEALTH: Server is healthy")
                return true
            } else {
                print("❌ HEALTH: Server returned status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
        } catch {
            print("❌ HEALTH: Server health check failed: \(error.localizedDescription)")
            return false
        }
    }
}