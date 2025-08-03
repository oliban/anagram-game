import SwiftUI

struct EmojiCollectionView: View {
    @ObservedObject var gameModel: GameModel
    @State private var emojiService = EmojiCollectionService.shared
    @State private var collectionSections: [EmojiCollectionSection] = []
    @State private var collectionSummary: EmojiCollectionSummary?
    @State private var selectedRarity: EmojiRarity?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with collection statistics
                headerView
                
                // Rarity filter tabs
                rarityFilterView
                
                // Collection content
                if isLoading {
                    loadingView
                } else if let errorMessage = errorMessage {
                    errorView(message: errorMessage)
                } else {
                    collectionGridView
                }
                
                Spacer()
            }
            .navigationTitle("Emoji Collection")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadCollection()
            }
            .refreshable {
                await loadCollection()
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            if let summary = collectionSummary {
                // Collection progress
                HStack {
                    VStack(alignment: .leading) {
                        Text("Collection Progress")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(summary.collectedEmojis)/\(summary.totalEmojis) emojis")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("\(Int(summary.completionPercentage))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                        
                        Text("\(summary.totalPoints) points")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Progress bar
                ProgressView(value: summary.completionPercentage, total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                // Rarity breakdown
                HStack(spacing: 16) {
                    ForEach(EmojiRarity.allCases, id: \.self) { rarity in
                        VStack {
                            Text("\(summary.collectionsByRarity[rarity] ?? 0)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color(hex: rarity.color))
                            
                            Text(rarity.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - Rarity Filter View
    
    private var rarityFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All filter
                FilterChip(
                    title: "All",
                    isSelected: selectedRarity == nil,
                    color: .accentColor
                ) {
                    selectedRarity = nil
                    filterCollection()
                }
                
                // Rarity filters
                ForEach(EmojiRarity.allCases, id: \.self) { rarity in
                    FilterChip(
                        title: rarity.displayName,
                        isSelected: selectedRarity == rarity,
                        color: Color(hex: rarity.color)
                    ) {
                        selectedRarity = rarity
                        filterCollection()
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Collection Grid View
    
    private var collectionGridView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredSections, id: \.id) { section in
                    if !section.emojis.isEmpty || selectedRarity == section.rarity {
                        raritySection(section)
                    }
                }
            }
            .padding()
        }
    }
    
    private func raritySection(_ section: EmojiCollectionSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(section.rarity.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: section.rarity.color))
                
                Spacer()
                
                Text("\(section.emojis.count)/\(section.totalInRarity)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Completion progress for this rarity
            ProgressView(value: section.completionPercentage, total: 100)
                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: section.rarity.color)))
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
            
            // Drop rate info
            Text("Drop Rate: \(section.rarity.dropRateRange)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Emoji grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(section.emojis, id: \.id) { collection in
                    EmojiCollectionCard(collection: collection)
                }
                
                // Show empty slots for uncollected emojis
                ForEach(0..<max(0, section.totalInRarity - section.emojis.count), id: \.self) { _ in
                    EmptyEmojiSlot()
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading your emoji collection...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Error Loading Collection")
                .font(.headline)
                .padding(.top)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    await loadCollection()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var filteredSections: [EmojiCollectionSection] {
        if let selectedRarity = selectedRarity {
            return collectionSections.filter { $0.rarity == selectedRarity }
        }
        return collectionSections
    }
    
    // MARK: - Methods
    
    private func loadCollection() async {
        guard let playerIdString = gameModel.playerId,
              let playerId = UUID(uuidString: playerIdString) else {
            errorMessage = "No valid player ID available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            async let sectionsTask = emojiService.getOrganizedCollection(for: playerId)
            async let summaryTask = emojiService.getCollectionSummary(for: playerId)
            
            collectionSections = try await sectionsTask
            collectionSummary = try await summaryTask
            
            DebugLogger.shared.ui("📚 Loaded emoji collection with \(collectionSections.count) rarity sections")
            
        } catch {
            errorMessage = error.localizedDescription
            DebugLogger.shared.error("❌ Failed to load emoji collection: \(error)")
        }
        
        isLoading = false
    }
    
    private func filterCollection() {
        // Collection is already organized by rarity, just need to trigger UI update
        // The filteredSections computed property handles the actual filtering
    }
}

// MARK: - Supporting Views

struct EmojiCollectionCard: View {
    let collection: PlayerEmojiCollection
    
    var body: some View {
        VStack(spacing: 4) {
            // Emoji character
            Text(collection.emoji?.emojiCharacter ?? "❓")
                .font(.title)
            
            // Discovery indicator
            if collection.isFirstGlobalDiscovery {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .frame(width: 50, height: 50)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(collection.emoji?.rarity.triggersGlobalDrop == true ? Color(hex: collection.emoji?.rarity.color ?? "#95A5A6") : Color.clear, lineWidth: 2)
        )
    }
}

struct EmptyEmojiSlot: View {
    var body: some View {
        VStack {
            Image(systemName: "questionmark")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(width: 50, height: 50)
        .background(Color(UIColor.quaternarySystemFill))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
        )
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color(UIColor.secondarySystemFill))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// Color extension is already defined in LegendsView.swift