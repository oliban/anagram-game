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
    let _ = true  // Development mode marker
    #else
    let _ = false // Production mode marker  
    #endif
    
    // Environment-aware configuration
    // Note: host values here are not used - actual hosts come from developmentConfig/productionConfig
    let gameServerConfig = ServiceInfo(port: 3000, host: "192.168.1.133")
    let webDashboardConfig = ServiceInfo(port: 3001, host: "192.168.1.133") 
    let linkGeneratorConfig = ServiceInfo(port: 3002, host: "192.168.1.133")
    let databaseConfig = ServiceInfo(port: 5432, host: "192.168.1.133")
    
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
    
    // Build-time environment configuration
    private static var isLocalServer: Bool {
        #if DEBUG
        // Debug builds use local server
        print("🔧 CONFIG: Using LOCAL server (Debug build)")
        return true
        #else
        // Release builds use production server
        print("🔧 CONFIG: Using PRODUCTION server (Release build)")
        return false
        #endif
    }
    
    // Server Configuration - dynamically loaded from shared config
    static var serverPort: String { 
        return String(sharedConfig.services.gameServer.port)
    }
    
    static var baseURL: String {
        let host = isLocalServer ? sharedConfig.development.host : sharedConfig.production.host
        // AWS ALB doesn't need port specification (uses standard port 80)
        let url = host.contains("amazonaws.com") ? "http://\(host)" : "http://\(host):\(serverPort)"
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