import SwiftUI

struct OnlinePlayersView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Online Players")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: refreshPlayers) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(.linear(duration: 1).repeatCount(isRefreshing ? .max : 0, autoreverses: false), value: isRefreshing)
                }
                .disabled(isRefreshing || !networkManager.isConnected)
            }
            
            // Player Count
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.secondary)
                
                Text("\(networkManager.onlinePlayers.count) players online")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Connection Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(networkManager.connectionStatus.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Players List
            if networkManager.onlinePlayers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No players online")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !networkManager.isConnected {
                        Text("Connect to server to see online players")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(networkManager.onlinePlayers) { player in
                            PlayerRowView(player: player, isCurrentPlayer: player.id == networkManager.currentPlayer?.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            setupWebSocketListeners()
        }
    }
    
    // MARK: - Computed Properties
    
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
    
    // MARK: - Methods
    
    private func refreshPlayers() {
        guard !isRefreshing && networkManager.isConnected else { return }
        
        isRefreshing = true
        
        Task {
            await networkManager.fetchOnlinePlayers()
            
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func setupWebSocketListeners() {
        // NetworkManager handles periodic updates and real-time Socket.IO events
        // No additional timer needed here to avoid duplicate API calls
        print("📡 OnlinePlayersView: Relying on NetworkManager's updates")
    }
}

struct PlayerRowView: View {
    let player: Player
    let isCurrentPlayer: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Player Avatar
            Circle()
                .fill(isCurrentPlayer ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(player.name.prefix(1)).uppercased())
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentPlayer ? .blue : .primary)
                )
            
            // Player Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(player.name)
                        .font(.subheadline)
                        .fontWeight(isCurrentPlayer ? .semibold : .regular)
                        .foregroundColor(isCurrentPlayer ? .blue : .primary)
                    
                    if isCurrentPlayer {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                HStack(spacing: 8) {
                    // Active Status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(player.isActive ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text(player.isActive ? "Active" : "Away")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Connection Time
                    Text("Connected \(timeAgoString(from: player.connectedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions (could add buttons for sending phrases/quakes here)
            if !isCurrentPlayer {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentPlayer ? Color.blue.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrentPlayer ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    OnlinePlayersView()
}