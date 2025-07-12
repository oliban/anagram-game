//
//  ContentView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SwiftData
import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {}

struct ContentView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var gameModel = GameModel()
    @State private var showingConnectionTest = false
    @State private var showingRegistration = false
    @State private var isPlayerRegistered = false
    
    var body: some View {
        Group {
            if isPlayerRegistered {
                // Show lobby as main interface after registration
                LobbyView(gameModel: gameModel)
            } else {
                // Show registration/connection flow
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 30) {
                        // App title
                        VStack(spacing: 8) {
                            Text("🏆 Anagram Game")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Competitive word puzzles")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Connection status
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(connectionStatusColor)
                                    .frame(width: 12, height: 12)
                                    .animation(.easeInOut(duration: 0.3), value: networkManager.connectionStatus)
                                
                                Text(networkManager.connectionStatus.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if showingConnectionTest {
                                VStack(spacing: 4) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    
                                    Text("Setting up multiplayer...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Registration button
                        if !showingConnectionTest && networkManager.connectionStatus != .connecting {
                            Button("Get Started") {
                                showingRegistration = true
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .padding(.horizontal, 40)
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingRegistration) {
            PlayerRegistrationView(isPresented: $showingRegistration)
        }
        .onAppear {
            print("📱 ContentView appeared - checking for existing player or showing registration")
            
            // Check if we have a stored player name from previous session
            if let storedName = UserDefaults.standard.string(forKey: "playerName") {
                print("📱 Found stored player name: \(storedName) - attempting auto-connect")
                Task {
                    await autoConnectWithStoredName(storedName)
                }
            } else {
                print("📱 No stored player name - showing registration")
                // Reset connection state and show registration
                networkManager.connectionStatus = .disconnected
                networkManager.isConnected = false
                showingRegistration = true
            }
        }
        .onChange(of: networkManager.currentPlayer) { oldValue, newValue in
            isPlayerRegistered = newValue != nil
            
            // Update gameModel with player information
            if let player = newValue {
                gameModel.playerId = player.id
                gameModel.playerName = player.name
                gameModel.networkManager = networkManager
                networkManager.gameModel = gameModel
            } else {
                // Player logged out - show registration
                print("🔴 LOGOUT: Player cleared, showing registration")
                showingRegistration = true
            }
            
            // Player list updates are handled by NetworkManager's periodic timer
            // No immediate refresh needed - reduces server load
        }
    }
    
    // MARK: - Auto Connect Methods
    
    private func autoConnectWithStoredName(_ playerName: String) async {
        print("🚀 Starting auto-connect with stored name: \(playerName)")
        
        // Show connecting state
        await MainActor.run {
            showingConnectionTest = true
            networkManager.connectionStatus = .connecting
        }
        
        // Test connection first
        print("🔍 Testing connection...")
        let connectionResult = await networkManager.testConnection()
        
        switch connectionResult {
        case .success:
            print("✅ Connection test successful - proceeding with registration")
            
            // Register with stored name
            let success = await networkManager.registerPlayerBool(name: playerName)
            
            await MainActor.run {
                showingConnectionTest = false
                
                if success {
                    isPlayerRegistered = true
                    print("✅ Auto-registered with stored name: \(playerName)")
                } else {
                    print("❌ Failed to register with stored name - showing registration")
                    showingRegistration = true
                }
            }
            
        case .failure(let error):
            print("❌ Connection test failed: \(error)")
            
            await MainActor.run {
                showingConnectionTest = false
                networkManager.connectionStatus = .error("Connection failed: \(error)")
                // Show registration view for manual retry
                showingRegistration = true
            }
        }
    }
    
    private func autoConnectAndRegister() async {
        print("🚀 Starting auto-connect process...")
        
        // Show connecting state
        await MainActor.run {
            print("🚀 Setting showingConnectionTest = true")
            showingConnectionTest = true
            networkManager.connectionStatus = .connecting
        }
        
        // Test connection first with timeout
        print("🔍 Testing connection...")
        let connectionResult = await networkManager.testConnection()
        
        switch connectionResult {
        case .success:
            print("✅ Connection test successful - proceeding with registration")
            
            // Establish WebSocket connection
            networkManager.connect()
            
            // Wait briefly for connection to establish
            try? await Task.sleep(nanoseconds: AppConfig.registrationStabilizationDelay)
            
            // For testing: always create a new random player name
            let randomPlayerName = "Player_\(Int.random(in: 100...999))"
            print("👤 Creating test player: \(randomPlayerName)")
            
            // Register with random name
            let success = await networkManager.registerPlayerBool(name: randomPlayerName)
            
            await MainActor.run {
                showingConnectionTest = false
                
                if success {
                    isPlayerRegistered = true
                    print("✅ Auto-registered test player: \(randomPlayerName)")
                } else {
                    print("❌ Failed to register test player")
                    showingRegistration = true
                }
            }
            
        case .failure(let error):
            print("❌ Connection test failed: \(error)")
            
            await MainActor.run {
                showingConnectionTest = false
                // Update connection status to show the specific error
                networkManager.connectionStatus = .error("Test failed: \(error)")
            }
        }
    }
    
    private var connectionStatusColor: Color {
        switch networkManager.connectionStatus {
        case .disconnected:
            return .red
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
