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
    let staging: EnvironmentConfig
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
    let description: String
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
    
    // Environment configurations
    let developmentConfig = EnvironmentConfig(host: "192.168.1.188", description: "Local Development Server")
    let stagingConfig = EnvironmentConfig(host: "lake-throwing-aluminium-ol.trycloudflare.com", description: "Pi Staging Server (Cloudflare tunnel)")
    let productionConfig = EnvironmentConfig(host: "anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com", description: "AWS Production Server")
    
    let config = SharedAppConfig(
        services: services,
        development: developmentConfig,
        staging: stagingConfig,
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
    
    // Environment detection - can be modified by build script
    private static var currentEnvironment: String {
        let env = "staging" // DEFAULT_ENVIRONMENT
        print("🔧 CONFIG: Using \(env.uppercased()) environment")
        return env
    }
    
    // Get current environment configuration
    private static var environmentConfig: EnvironmentConfig {
        switch currentEnvironment {
        case "local":
            return sharedConfig.development
        case "staging":
            return sharedConfig.staging
        case "aws":
            return sharedConfig.production
        default:
            print("⚠️ CONFIG: Unknown environment '\(currentEnvironment)', falling back to local")
            return sharedConfig.development
        }
    }
    
    // Server Configuration - dynamically loaded from shared config
    static var serverPort: String { 
        return String(sharedConfig.services.gameServer.port)
    }
    
    static var baseURL: String {
        let config = environmentConfig
        let host = config.host
        
        // Determine URL format based on host type and environment
        let url: String
        if host.contains("amazonaws.com") {
            // AWS ELB - no port needed
            url = "http://\(host)"
        } else if host.contains("trycloudflare.com") {
            // Cloudflare tunnel - HTTPS, no port needed
            url = "https://\(host)"
        } else if host == "STAGING_PLACEHOLDER" {
            // Staging placeholder - this means tunnel URL wasn't set
            url = "http://192.168.1.222:3000"  // Fallback to Pi local IP
            print("⚠️ CONFIG: Staging tunnel URL not set, falling back to Pi local IP")
        } else {
            // Local or Pi staging server - needs port
            let port = sharedConfig.services.gameServer.port
            url = "http://\(host):\(port)"
        }
        
        print("🔧 CONFIG: Using \(currentEnvironment.uppercased()) server: \(url)")
        print("🔧 CONFIG: Environment: \(config.description)")
        return url
    }
    
    // Contribution system URLs (link-generator service) 
    static var contributionBaseURL: String {
        let config = environmentConfig
        let host = config.host
        let port = sharedConfig.services.linkGenerator.port
        
        // Use same logic as baseURL for contribution system
        if host.contains("amazonaws.com") {
            return "http://\(host)"
        } else if host.contains("trycloudflare.com") {
            return "https://\(host)"
        } else if host == "STAGING_PLACEHOLDER" {
            return "http://192.168.1.222:\(port)"  // Fallback to Pi local IP
        } else {
            return "http://\(host):\(port)"
        }
    }
    
    static var contributionAPIURL: String {
        return "\(contributionBaseURL)/api/contribution/request"
    }
    
    // Timing Configuration
    static let connectionRetryDelay: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds
    static let registrationStabilizationDelay: UInt64 = 1_000_000_000  // 1 second in nanoseconds
    static let playerListRefreshInterval: TimeInterval = 15.0  // 15 seconds
    static let notificationDisplayDuration: TimeInterval = 3.0  // 3 seconds
    
    // Performance Monitoring Configuration - Disabled by default to reduce API calls
    static var isPerformanceMonitoringEnabled: Bool = {
        // Default to disabled for cleaner startup behavior
        // Can be enabled later if needed for debugging
        return false
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
