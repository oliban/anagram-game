//
//  ContentView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SwiftData
import Foundation
import os.log


struct ContentView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var gameModel = GameModel()
    @State private var showingRegistration = false
    
    // Create os_log for this subsystem
    private let logger = Logger(subsystem: "com.fredrik.anagramgame", category: "ContentView")
    
    var body: some View {
        LobbyView(gameModel: gameModel)
            .sheet(isPresented: $showingRegistration) {
                PlayerRegistrationView(isPresented: $showingRegistration)
            }
            .onAppear {
                // Initialize gameModel with networkManager immediately
                gameModel.networkManager = networkManager
                networkManager.gameModel = gameModel
                
                print("📱 ContentView appeared - checking for existing player or showing registration")
                logger.info("📱 [OS_LOG] ContentView appeared - checking for existing player or showing registration")
                DebugLogger.shared.ui("ContentView appeared - checking for existing player or showing registration")
                
                // First, fetch server configuration
                Task {
                    _ = try? await networkManager.fetchServerConfig()
                    
                    // Then check if we have a stored player name from previous session
                    if let storedName = UserDefaults.standard.string(forKey: "playerName") {
                        print("📱 Found stored player name: \(storedName) - attempting auto-connect")
                        await autoConnectWithStoredName(storedName)
                    } else {
                        print("📱 No stored player name - showing registration")
                        // Reset connection state and show registration
                        await MainActor.run {
                            networkManager.connectionStatus = .disconnected
                            networkManager.isConnected = false
                            showingRegistration = true
                        }
                    }
                }
            }
            .onChange(of: networkManager.currentPlayer) { oldValue, newValue in
                // Update gameModel with player information
                if let player = newValue {
                    gameModel.playerId = player.id
                    gameModel.playerName = player.name
                    gameModel.networkManager = networkManager
                    networkManager.gameModel = gameModel
                    
                    // Load total score from local storage and then refresh from server
                    gameModel.loadTotalScore()
                    
                    // Start the first game after registration is complete
                    // Wait for phrases to be loaded first
                    Task { @MainActor in
                        await gameModel.refreshPhrasesForLobby()
                        await gameModel.startNewGame()
                    }
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
        DebugLogger.shared.network("Starting auto-connect with stored name: \(playerName)")
        
        do {
            // Show connecting state
            await MainActor.run {
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
                    if success {
                        print("✅ Auto-registered with stored name: \(playerName)")
                        logger.info("✅ [OS_LOG] Auto-registered with stored name: \(playerName)")
                        DebugLogger.shared.network("Auto-registered with stored name: \(playerName)")
                    } else {
                        print("❌ Failed to register with stored name - showing registration")
                        networkManager.connectionStatus = .disconnected
                        showingRegistration = true
                    }
                }
                
            case .failure(let error):
                print("❌ Connection test failed: \(error)")
                DebugLogger.shared.error("Auto-connect failed - connection test error: \(error)")
                
                await MainActor.run {
                    networkManager.connectionStatus = .error("Connection failed: \(error)")
                    // Show registration view for manual retry
                    showingRegistration = true
                }
            }
        } catch {
            print("❌ AUTOCONNECT: Unexpected error during auto-connect: \(error)")
            DebugLogger.shared.error("Auto-connect unexpected error: \(error)")
            
            await MainActor.run {
                networkManager.connectionStatus = .error("Auto-connect failed")
                showingRegistration = true
            }
        }
    }
    
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
