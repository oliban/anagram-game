//
//  NetworkConfiguration.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from NetworkManager.swift during refactoring
//

import Foundation

// MARK: - Configuration Models

struct SharedAppConfig: Codable {
    let services: ServiceConfig
    let development: EnvironmentConfig
    let production: EnvironmentConfig
}

struct ServiceConfig: Codable {
    let gameServer: ServiceInfo
    let webDashboard: ServiceInfo
    let linkGenerator: ServiceInfo
    let database: ServiceInfo
}

struct ServiceInfo: Codable {
    let port: Int
    let host: String
}

struct EnvironmentConfig: Codable {
    let host: String
}

// MARK: - Configuration Loader

private func loadSharedConfig() -> SharedAppConfig {
    guard let path = Bundle.main.path(forResource: "app-config", ofType: "json"),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let config = try? JSONDecoder().decode(SharedAppConfig.self, from: data) else {
        fatalError("❌ CONFIG: Failed to load app-config.json from bundle. Configuration is required.")
    }
    print("✅ CONFIG: Loaded shared configuration from bundle")
    return config
}

// MARK: - App Configuration

struct AppConfig {
    private static let sharedConfig = loadSharedConfig()
    
    // Server Configuration - dynamically loaded from shared config
    static var serverPort: String { 
        return String(sharedConfig.services.gameServer.port)
    }
    
    static var baseURL: String {
        let host = sharedConfig.development.host
        return "http://\(host):\(serverPort)"
    }
    
    // Contribution system URLs (link-generator service) 
    static var contributionBaseURL: String {
        let host = sharedConfig.development.host
        let port = sharedConfig.services.linkGenerator.port
        return "http://\(host):\(port)"
    }
    
    static var contributionAPIURL: String {
        return "\(contributionBaseURL)/api/contribution/request"
    }
    
    // Timing Configuration
    static let connectionRetryDelay: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds
    static let registrationStabilizationDelay: UInt64 = 1_000_000_000  // 1 second in nanoseconds
    static let playerListRefreshInterval: TimeInterval = 15.0  // 15 seconds
    static let notificationDisplayDuration: TimeInterval = 3.0  // 3 seconds
    
    // Performance Monitoring Configuration - Server-driven
    static var isPerformanceMonitoringEnabled: Bool = {
        // Default fallback based on build type
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
    
    // Update performance monitoring based on server configuration
    static func updatePerformanceMonitoringFromServer(_ enabled: Bool) {
        isPerformanceMonitoringEnabled = enabled
        print("⚙️ CONFIG: Performance monitoring \(enabled ? "enabled" : "disabled") by server")
        
        // Notify observers that configuration has changed
        NotificationCenter.default.post(name: .performanceMonitoringConfigChanged, object: enabled)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let performanceMonitoringConfigChanged = Notification.Name("performanceMonitoringConfigChanged")
}