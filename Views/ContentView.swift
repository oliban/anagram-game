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
    @State private var showingConnectionTest = false
    @State private var showingRegistration = false
    @State private var showingPlayersList = false
    @State private var showingPhraseCreation = false
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
                            
                            HStack(spacing: 12) {
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
                                
                                Button(action: {
                                    showingPhraseCreation = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.message.fill")
                                        Text("Send Phrase")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.green)
                                }
                                .disabled(networkManager.onlinePlayers.filter { $0.id != networkManager.currentPlayer?.id }.isEmpty)
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
                            networkManager.connectionStatus = .connecting
                            Task {
                                let result = await networkManager.testConnection()
                                await MainActor.run {
                                    switch result {
                                    case .success:
                                        networkManager.connectionStatus = .connected
                                        Task {
                                            let success = await networkManager.registerPlayer(name: "Player_\(Int.random(in: 100...999))")
                                            if !success {
                                                networkManager.connectionStatus = .error("Registration failed")
                                            }
                                        }
                                    case .failure(let error):
                                        networkManager.connectionStatus = .error("Test failed: \(error)")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .disabled(showingConnectionTest)
                        
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
        .sheet(isPresented: $showingPhraseCreation) {
            PhraseCreationView(isPresented: $showingPhraseCreation)
        }
        .onAppear {
            print("📱 ContentView appeared - skipping auto-connect for debugging")
            // Just reset state, don't auto-connect
            networkManager.connectionStatus = .disconnected
            networkManager.isConnected = false
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
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // For testing: always create a new random player name
            let randomPlayerName = "Player_\(Int.random(in: 100...999))"
            print("👤 Creating test player: \(randomPlayerName)")
            
            // Register with random name
            let success = await networkManager.registerPlayer(name: randomPlayerName)
            
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
