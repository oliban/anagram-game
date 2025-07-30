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
    // Dynamic configuration based on build environment
    // No static JSON file needed - configuration is determined at build time
    
    #if DEBUG
    let isDevelopment = true
    #else
    let isDevelopment = false
    #endif
    
    // Environment-aware configuration
    let gameServerConfig = ServiceInfo(port: 3000, host: "localhost")
    let webDashboardConfig = ServiceInfo(port: 3001, host: "localhost") 
    let linkGeneratorConfig = ServiceInfo(port: 3002, host: "localhost")
    let databaseConfig = ServiceInfo(port: 5432, host: "localhost")
    
    let services = ServiceConfig(
        gameServer: gameServerConfig,
        webDashboard: webDashboardConfig,
        linkGenerator: linkGeneratorConfig,
        database: databaseConfig
    )
    
    // Use IP address for local development so physical devices can connect
    let developmentConfig = EnvironmentConfig(host: "192.168.1.133")
    let productionConfig = EnvironmentConfig(host: "anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com")
    
    let config = SharedAppConfig(
        services: services,
        development: developmentConfig,
        production: productionConfig
    )
    
    #if DEBUG
    print("✅ CONFIG: Generated dynamic configuration for development")
    #else
    print("✅ CONFIG: Generated dynamic configuration for production")
    #endif
    return config
}

// MARK: - App Configuration

struct AppConfig {
    private static let sharedConfig = loadSharedConfig()
    
    // Dynamic environment detection based on build settings
    private static var isLocalServer: Bool {
        // Simple runtime detection - check if we can reach local server
        // If local server is available, use it; otherwise use production
        // This is more reliable than build-time macros
        
        // For development builds, check if local services are running
        let localURL = "http://192.168.1.133:3000"
        
        // Quick sync check - if we're in a local development environment
        // the local server should be running
        let url = URL(string: "\(localURL)/api/status")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0 // Very quick timeout
        
        let semaphore = DispatchSemaphore(value: 0)
        var isLocalAvailable = false
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, 
               httpResponse.statusCode == 200 {
                isLocalAvailable = true
            }
            semaphore.signal()
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        print("🔍 CONFIG: Local server check - \(isLocalAvailable ? "AVAILABLE" : "UNAVAILABLE")")
        return isLocalAvailable
    }
    
    // Server Configuration - dynamically loaded from shared config
    static var serverPort: String { 
        return String(sharedConfig.services.gameServer.port)
    }
    
    static var baseURL: String {
        let host = isLocalServer ? sharedConfig.development.host : sharedConfig.production.host
        let url = "http://\(host):\(serverPort)"
        print("🔧 CONFIG: Using \(isLocalServer ? "LOCAL" : "AWS") server: \(url)")
        return url
    }
    
    // Contribution system URLs (link-generator service) 
    static var contributionBaseURL: String {
        let host = isLocalServer ? sharedConfig.development.host : sharedConfig.production.host
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