import SwiftUI
import Foundation

struct LegendsView: View {
    @ObservedObject var gameModel: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var legendPlayers: [LegendPlayer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header section
                    headerSection
                    
                    // Legend players list
                    legendPlayersSection
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("🏆 Legends")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                trailing: Button("Done") {
                    dismiss()
                }
            )
        }
        .onAppear {
            Task {
                await loadLegendPlayers()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Hall of Fame")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text("These are the mighty players who have reached the wretched skill level and beyond")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Legend Players Section
    private var legendPlayersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("Legendary Players")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading legends...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .padding()
            } else if legendPlayers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "crown")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No legends yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Be the first to reach wretched skill level!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 12) {
                    ForEach(Array(legendPlayers.enumerated()), id: \.offset) { index, player in
                        LegendPlayerCard(
                            player: player,
                            position: index + 1,
                            isCurrentPlayer: player.name == gameModel.playerName
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Data Loading
    private func loadLegendPlayers() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        guard let networkManager = gameModel.networkManager else {
            await MainActor.run {
                errorMessage = "Network manager not available"
                isLoading = false
            }
            return
        }
        
        do {
            let players = try await networkManager.getLegendPlayers()
            await MainActor.run {
                self.legendPlayers = players
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Supporting Views

struct LegendPlayerCard: View {
    let player: LegendPlayer
    let position: Int
    let isCurrentPlayer: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Position and crown
            HStack {
                ZStack {
                    Circle()
                        .fill(positionColor)
                        .frame(width: 28, height: 28)
                    Text("\(position)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                // Player name
                Text(player.name)
                    .font(.body)
                    .fontWeight(isCurrentPlayer ? .bold : .semibold)
                    .foregroundColor(isCurrentPlayer ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Skill title
                Text(player.skillTitle.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                
                // Statistics
                VStack(spacing: 4) {
                    HStack {
                        Text("Score:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(player.totalScore)")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Phrases:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(player.phrasesCompleted)")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Level:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(player.skillLevel)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(12)
        .background(isCurrentPlayer ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentPlayer ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var positionColor: Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
}

// MARK: - Data Models
// LegendPlayer is defined in NetworkManager.swift

#Preview {
    LegendsView(gameModel: GameModel())
}