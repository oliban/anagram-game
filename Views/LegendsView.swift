import SwiftUI
import Foundation

struct LegendsView: View {
    @ObservedObject var gameModel: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var legendPlayers: [LegendPlayer] = []
    @State private var minimumSkillTitle: String = "Wretched"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var globalEmojiStats: GlobalEmojiStatsResponse?
    @State private var emojiService = EmojiCollectionService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header section
                    headerSection
                    
                    // Top 5 rarest emojis section
                    rarestEmojisSection
                    
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
                await loadGlobalEmojiStats()
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
            
            Text("These are the mighty players who have reached the \(minimumSkillTitle) skill level and beyond")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Rarest Emojis Section
    private var rarestEmojisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Legendary Emojis")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if let globalStats = globalEmojiStats {
                VStack(spacing: 12) {
                    Text("The 5 rarest emojis ever discovered")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Array(globalStats.topRarestEmojis.prefix(5).enumerated()), id: \.offset) { index, discovery in
                            RareEmojiCard(discovery: discovery, rank: index + 1)
                        }
                    }
                    
                    if globalStats.totalDiscoveries > 0 {
                        Text("Total global discoveries: \(globalStats.totalDiscoveries)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading legendary emojis...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
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
                    Text("Be the first to reach \(minimumSkillTitle) skill level!")
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
            let response = try await networkManager.getLegendPlayers()
            await MainActor.run {
                self.legendPlayers = response.players
                self.minimumSkillTitle = response.minimumSkillTitle
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func loadGlobalEmojiStats() async {
        do {
            let stats = try await emojiService.getGlobalStats()
            await MainActor.run {
                self.globalEmojiStats = stats
            }
            DebugLogger.shared.ui("📊 Loaded global emoji stats: \(stats.topRarestEmojis.count) rare emojis")
        } catch {
            DebugLogger.shared.error("❌ Failed to load global emoji stats: \(error)")
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
                Text(player.skillTitle)
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

struct RareEmojiCard: View {
    let discovery: EmojiGlobalDiscovery
    let rank: Int
    
    var body: some View {
        VStack(spacing: 6) {
            // Rank indicator
            Text("#\(rank)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            // Emoji character
            Text(discovery.emoji?.emojiCharacter ?? "❓")
                .font(.title2)
            
            // First discoverer indicator
            if discovery.firstDiscoverer != nil {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
            
            // Rarity indicator
            if let emoji = discovery.emoji {
                Circle()
                    .fill(Color(hex: emoji.rarity.color))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 60, height: 80)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(discovery.emoji?.rarity == .legendary ? Color.yellow : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Data Models
// LegendPlayer is defined in NetworkManager.swift

#Preview {
    LegendsView(gameModel: GameModel())
}