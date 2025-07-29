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
            .log(false),
            .compress,
            .connectParams(["transport": "websocket"]),
            .forceWebsockets(true)
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
        }
        
        // Delegate to services for specific events
        socket.on("playersUpdate") { [weak self] data, _ in
            self?.playerDelegate?.handlePlayerListUpdate(data: data)
        }
        
        socket.on("phraseReceived") { [weak self] data, _ in
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
        
        print("🔌 SOCKET: Connecting with player ID: \(playerId)")
        connectionStatus = .connecting
        
        socket.connect(withPayload: ["playerId": playerId])
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