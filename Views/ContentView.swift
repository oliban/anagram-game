//
//  ContentView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SwiftData
import Foundation

struct ContentView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @State private var showingConnectionTest = false
    @State private var showingRegistration = false
    @State private var showingPlayersList = false
    @State private var isPlayerRegistered = false
    
    var body: some View {
        ZStack {
            PhysicsGameView()
            
            // Connection Status Indicator
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 4) {
                        // Connection Status Circle
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: networkManager.connectionStatus)
                        
                        // Connection Status Text
                        Text(networkManager.connectionStatus.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60) // Below notch/status bar
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    if isPlayerRegistered {
                        VStack(spacing: 8) {
                            Text("Welcome, \(networkManager.currentPlayer?.name ?? "Player")!")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Button(action: {
                                showingPlayersList = true
                            }) {
                                HStack {
                                    Image(systemName: "person.2.fill")
                                    Text("\(networkManager.onlinePlayers.count) players online")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                    } else if showingConnectionTest {
                        VStack(spacing: 4) {
                            Text("Connecting...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Setting up multiplayer...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Debug/Testing buttons
                    VStack(spacing: 8) {
                        Button("Test Connection") {
                            showingConnectionTest = true
                            Task {
                                let result = await networkManager.testConnection()
                                switch result {
                                case .success:
                                    networkManager.connect()
                                case .failure(let error):
                                    print("Connection test failed: \(error)")
                                }
                                showingConnectionTest = false
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .disabled(showingConnectionTest)
                        
                        // Manual ping test button
                        Button("Send Manual Ping") {
                            networkManager.sendManualPing()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .disabled(!networkManager.isConnected)
                        
                        // Debug: Reset registration
                        Button("Reset Player Data") {
                            UserDefaults.standard.removeObject(forKey: "playerName")
                            networkManager.disconnect()
                            networkManager.currentPlayer = nil
                            isPlayerRegistered = false
                            
                            // Auto-reconnect after reset
                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                await autoConnectAndRegister()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .font(.caption)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingRegistration) {
            PlayerRegistrationView(isPresented: $showingRegistration)
        }
        .sheet(isPresented: $showingPlayersList) {
            NavigationView {
                OnlinePlayersView()
                    .navigationTitle("Online Players")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingPlayersList = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            // Check if player is already registered
            if networkManager.currentPlayer == nil {
                // For testing, auto-register if not registered
                // In a real app, you might show the registration sheet
                Task {
                    let success = await networkManager.registerPlayer(name: "Player_\(Int.random(in: 100...999))")
                    if success {
                        print("TEMP: Auto-registered player")
                    }
                }
            } else {
                // If already registered, ensure we are connected
                if let player = networkManager.currentPlayer {
                    networkManager.connect(playerId: player.id)
                }
            }
        }
        .onChange(of: networkManager.currentPlayer) { oldValue, newValue in
            isPlayerRegistered = newValue != nil
            
            // Player list updates are handled by NetworkManager's periodic timer
            // No immediate refresh needed - reduces server load
        }
    }
    
    // MARK: - Auto Connect Methods
    
    private func autoConnectAndRegister() async {
        print("🚀 Starting auto-connect process...")
        
        // Show connecting state
        await MainActor.run {
            showingConnectionTest = true
        }
        
        // Test connection first
        let connectionResult = await networkManager.testConnection()
        
        switch connectionResult {
        case .success:
            print("✅ Connection test successful")
            
            // Establish WebSocket connection
            networkManager.connect()
            
            // Wait briefly for connection to establish
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Check if user has saved player name
            if let savedPlayerName = UserDefaults.standard.string(forKey: "playerName"),
               !savedPlayerName.isEmpty {
                print("👤 Found saved player name: \(savedPlayerName)")
                
                // Register with existing name
                let success = await networkManager.registerPlayer(name: savedPlayerName)
                
                await MainActor.run {
                    showingConnectionTest = false
                    
                    if success {
                        isPlayerRegistered = true
                        print("✅ Auto-registered returning player: \(savedPlayerName)")
                    } else {
                        print("❌ Failed to register returning player")
                        // Clear invalid saved name and show registration
                        UserDefaults.standard.removeObject(forKey: "playerName")
                        showingRegistration = true
                    }
                }
            } else {
                print("👤 No saved player name - first time user")
                
                await MainActor.run {
                    showingConnectionTest = false
                    isPlayerRegistered = false
                    showingRegistration = true
                }
            }
            
        case .failure(let error):
            print("❌ Connection test failed: \(error)")
            
            await MainActor.run {
                showingConnectionTest = false
                // Keep UI in disconnected state
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
