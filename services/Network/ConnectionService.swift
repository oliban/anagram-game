//
//  ConnectionService.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Handles Socket.IO connection management and lifecycle
//

import Foundation
import SocketIO
import UIKit

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

class ConnectionService: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isConnected: Bool = false
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let baseURL = AppConfig.baseURL
    private var pendingPlayerId: String?
    
    // Delegates for handling socket events
    weak var playerDelegate: PlayerServiceDelegate?
    weak var phraseDelegate: PhraseServiceDelegate?
    
    init() {
        setupSocketManager()
        setupAppLifecycleMonitoring()
    }
    
    // MARK: - Socket Setup
    
    private func setupSocketManager() {
        guard let url = URL(string: baseURL) else {
            print("❌ SOCKET: Invalid base URL: \(baseURL)")
            connectionStatus = .error("Invalid server URL")
            return
        }
        
        let config: SocketIOClientConfiguration = [
            .log(true),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1), // Keep trying forever
            .reconnectWait(3),     // Wait 3 seconds before reconnecting
            .reconnectWaitMax(10), // Max wait 10 seconds
            .forceWebsockets(true),// Use WebSockets only, no long-polling fallback
            .secure(false)         // Set to true for https
        ]
        
        manager = SocketManager(socketURL: url, config: config)
        socket = manager?.defaultSocket
        
        print("✅ SOCKET: Manager configured for \(baseURL)")
        setupSocketEventHandlers()
    }
    
    private func setupSocketEventHandlers() {
        guard let socket = socket else { return }
        
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("✅ SOCKET: Connected to server")
            DispatchQueue.main.async {
                self?.connectionStatus = .connected
                self?.isConnected = true
            }
            
            // Emit player-connect event if we have a pending player ID
            if let playerId = self?.pendingPlayerId {
                print("🔌 SOCKET: Emitting player-connect event for \(playerId)")
                self?.socket?.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            print("🔌 SOCKET: Disconnected from server")
            DispatchQueue.main.async {
                self?.connectionStatus = .disconnected
                self?.isConnected = false
            }
        }
        
        socket.on(clientEvent: .error) { [weak self] data, _ in
            if let errorData = data.first {
                print("❌ SOCKET: Connection error - \(errorData)")
                DispatchQueue.main.async {
                    self?.connectionStatus = .error("Connection error")
                    self?.isConnected = false
                }
            }
        }
        
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            print("🔄 SOCKET: Reconnected to server")
            DispatchQueue.main.async {
                self?.connectionStatus = .connected
                self?.isConnected = true
            }
            
            // Re-emit player-connect event on reconnection
            if let playerId = self?.pendingPlayerId {
                print("🔄 SOCKET: Re-emitting player-connect event after reconnection for \(playerId)")
                self?.socket?.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            }
        }
        
        // Handle connection errors from server
        socket.on("connection-error") { [weak self] data, _ in
            if let errorData = data.first as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                print("❌ SOCKET: Server connection error: \(errorMessage)")
                DispatchQueue.main.async {
                    self?.connectionStatus = .error(errorMessage)
                    self?.isConnected = false
                }
            }
        }
        
        // Handle successful player connection confirmation
        socket.on("player-connected") { [weak self] data, _ in
            if let confirmData = data.first as? [String: Any],
               let success = confirmData["success"] as? Bool, success {
                print("✅ SOCKET: Player connection confirmed by server")
            }
        }
        
        // Delegate to services for specific events
        socket.on("player-list-updated") { [weak self] data, _ in
            self?.playerDelegate?.handlePlayerListUpdate(data: data)
        }
        
        socket.on("new-phrase") { [weak self] data, _ in
            self?.phraseDelegate?.handleNewPhrase(data: data)
        }
        
        socket.on("phraseCompleted") { [weak self] data, _ in
            self?.phraseDelegate?.handlePhraseCompletionNotification(data: data)
        }
    }
    
    // MARK: - Connection Management
    
    func connect(playerId: String) {
        guard let socket = socket else {
            print("❌ SOCKET: Socket not initialized")
            return
        }
        
        print("🔌 SOCKET: Attempting connection to \(baseURL) with player ID: \(playerId)")
        print("🔌 SOCKET: Socket state before connect: \(socket.status)")
        
        // Store the player ID for the player-connect event
        pendingPlayerId = playerId
        
        if socket.status == .connected {
            // If already connected, just send the player-connect event
            print("🔌 SOCKET: Already connected, emitting player-connect event")
            socket.emit("player-connect", with: [["playerId": playerId]], completion: nil)
            return
        }
        
        connectionStatus = .connecting
        socket.connect()
        print("🔌 SOCKET: Connect() called - will emit player-connect on successful connection")
    }
    
    func disconnect() {
        socket?.disconnect()
        print("🔌 SOCKET: Disconnected")
    }
    
    // MARK: - App Lifecycle Monitoring
    
    private func setupAppLifecycleMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppBecameActive() {
        print("📱 APP: Became active - maintaining socket connection")
        // Socket.IO will automatically reconnect if needed
    }
    
    @objc private func handleAppEnteredBackground() {
        print("📱 APP: Entered background - socket will remain connected")
        // Keep socket connected for real-time updates
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        socket?.disconnect()
    }
}

// MARK: - Service Delegate Protocols

protocol PlayerServiceDelegate: AnyObject {
    func handlePlayerListUpdate(data: [Any])
}

protocol PhraseServiceDelegate: AnyObject {
    func handleNewPhrase(data: [Any])
    func handlePhraseCompletionNotification(data: [Any])
}