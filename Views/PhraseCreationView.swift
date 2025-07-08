import SwiftUI

struct PhraseCreationView: View {
    @Binding var isPresented: Bool
    @StateObject private var networkManager = NetworkManager.shared
    
    @State private var phraseText = ""
    @State private var clueText = ""
    @State private var selectedPlayers: [Player] = []
    @State private var playerSearchText = ""
    @State private var showingSuggestions = false
    @State private var isAvailableToAll = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showingAlert = false
    @State private var currentDifficulty: DifficultyAnalysis? = nil
    @State private var isAnalyzingDifficulty = false
    @State private var debounceTimer: Timer?
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isPhraseFieldFocused: Bool
    @FocusState private var isClueFieldFocused: Bool
    
    // Computed property to check if any field is focused
    private var isAnyFieldFocused: Bool {
        return isSearchFieldFocused || isPhraseFieldFocused || isClueFieldFocused
    }
    
    private var wordCount: Int {
        phraseText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }
    
    private var isValidPhrase: Bool {
        let words = wordCount
        let hasPhrase = !phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasClue = !clueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return words >= 2 && words <= 6 && hasPhrase && hasClue
    }
    
    private var isValidPhraseForDifficulty: Bool {
        let words = wordCount
        let hasPhrase = !phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return words >= 2 && words <= 6 && hasPhrase
    }
    
    private var availableTargets: [Player] {
        networkManager.onlinePlayers.filter { $0.id != networkManager.currentPlayer?.id }
    }
    
    private var filteredPlayers: [Player] {
        guard playerSearchText.count >= 2 else { return [] }
        let searchText = playerSearchText.lowercased()
        return availableTargets.filter { player in
            player.name.lowercased().contains(searchText) && !selectedPlayers.contains(where: { $0.id == player.id })
        }
    }
    
    private var shouldShowSuggestions: Bool {
        return playerSearchText.count >= 2 && !filteredPlayers.isEmpty && showingSuggestions
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Send Custom Phrase")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Create an anagram puzzle for one or more players")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Phrase input section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Phrase (2-6 words)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter your phrase...", text: $phraseText, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(2...4)
                            .frame(minHeight: 44)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .focused($isPhraseFieldFocused)
                            .foregroundColor(.primary)
                            .accentColor(.blue)
                        
                        HStack {
                            Text("\(wordCount) words")
                                .font(.caption)
                                .foregroundColor(isValidPhrase ? .green : .primary)
                            
                            Spacer()
                            
                            if wordCount > 6 {
                                Text("Too many words")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else if wordCount > 0 && wordCount < 2 {
                                Text("Need at least 2 words")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // Real-time difficulty display
                        if isValidPhraseForDifficulty {
                            HStack {
                                if isAnalyzingDifficulty {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Analyzing difficulty...")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                } else if let difficulty = currentDifficulty {
                                    HStack {
                                        Text("Difficulty:")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        
                                        Text(difficulty.difficulty)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(difficultyColor(difficulty.difficulty))
                                        
                                        Text("(\(String(format: "%.1f", difficulty.score)))")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                
                // Clue input section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clue")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter a helpful clue...", text: $clueText, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(1...3)
                            .frame(minHeight: 44)
                            .autocapitalization(.sentences)
                            .focused($isClueFieldFocused)
                            .foregroundColor(.primary)
                            .accentColor(.blue)
                        
                        HStack {
                            Text("This clue will be revealed when the player uses Hint 3")
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if !clueText.isEmpty {
                                Text("✓")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                // Player availability section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send to Players")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Available to all players checkbox
                    Button(action: {
                        isAvailableToAll.toggle()
                        if isAvailableToAll {
                            selectedPlayers.removeAll()
                            playerSearchText = ""
                            showingSuggestions = false
                        }
                    }) {
                        HStack {
                            Image(systemName: isAvailableToAll ? "checkmark.square.fill" : "square")
                                .foregroundColor(isAvailableToAll ? .blue : .gray)
                            Text("Available to all players")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isAvailableToAll ? Color.blue.opacity(0.2) : Color(.systemGray4))
                    .cornerRadius(8)
                    
                    if availableTargets.isEmpty {
                        Text("No other players online")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding()
                            .background(Color(.systemGray4))
                            .cornerRadius(8)
                    } else if !isAvailableToAll {
                        VStack(alignment: .leading, spacing: 8) {
                            // Search field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search players...", text: $playerSearchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .focused($isSearchFieldFocused)
                                    .foregroundColor(.primary)
                                    .accentColor(.blue)
                                    .onTapGesture {
                                        showingSuggestions = true
                                    }
                                
                                if !playerSearchText.isEmpty {
                                    Button(action: {
                                        playerSearchText = ""
                                        showingSuggestions = false
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray4))
                            .cornerRadius(8)
                            
                            // Suggestions dropdown
                            if shouldShowSuggestions {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(filteredPlayers, id: \.id) { player in
                                        Button(action: {
                                            selectPlayer(player)
                                        }) {
                                            HStack {
                                                Image(systemName: "person.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.system(size: 16))
                                                Text(player.name)
                                                    .foregroundColor(.primary)
                                                    .font(.system(size: 16))
                                                Spacer()
                                                Text("Tap to select")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .cornerRadius(12)
                            }
                            
                            // Selected players
                            if !selectedPlayers.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Selected players:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 6) {
                                        ForEach(selectedPlayers, id: \.id) { player in
                                            HStack(spacing: 4) {
                                                Text(player.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                
                                                Button(action: {
                                                    removePlayer(player)
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.caption2)
                                                        .foregroundColor(.white)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            // Hint text
                            Text("Type at least 2 characters to search for players")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        }
                    }
                }
                
                Spacer()
                
                // Keyboard dismiss button (only show when keyboard is visible)
                if isAnyFieldFocused {
                    Button(action: {
                        dismissKeyboard()
                    }) {
                        HStack {
                            Image(systemName: "keyboard.chevron.compact.down")
                            Text("Dismiss Keyboard")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    // Send button
                    Button(action: {
                        dismissKeyboard()
                        sendPhrase()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isLoading ? "Sending..." : "Send Phrase")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSendPhrase ? Color.blue : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!canSendPhrase || isLoading)
                    
                    // Cancel button
                    Button("Cancel") {
                        dismissKeyboard()
                        isPresented = false
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
            .padding()
            .navigationBarHidden(true)
            .background(Color(.systemBackground))
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                dismissKeyboard()
                showingSuggestions = false
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text(successMessage.isEmpty ? "Error" : "Success"),
                    message: Text(successMessage.isEmpty ? errorMessage : successMessage),
                    dismissButton: .default(Text("OK")) {
                        if !successMessage.isEmpty {
                            isPresented = false
                        }
                    }
                )
            }
        }
        .onAppear {
            // Auto-select first available target if only one exists
            if availableTargets.count == 1 {
                selectedPlayers.append(availableTargets[0])
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            debounceTimer?.invalidate()
        }
        .onChange(of: phraseText) { _, newValue in
            // Cancel existing timer
            debounceTimer?.invalidate()
            
            // Clear state if phrase is invalid
            if !isValidPhraseForDifficulty {
                currentDifficulty = nil
                isAnalyzingDifficulty = false
                return
            }
            
            // Start new timer for debounced analysis
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                Task {
                    await analyzeDifficultyAsync(newValue)
                }
            }
        }
        .onChange(of: playerSearchText) { _, newValue in
            // Show suggestions when typing, hide when empty
            showingSuggestions = !newValue.isEmpty
        }
    }
    
    private var canSendPhrase: Bool {
        if isAvailableToAll {
            return isValidPhrase && !availableTargets.isEmpty
        } else {
            return isValidPhrase && !selectedPlayers.isEmpty && !availableTargets.isEmpty
        }
    }
    
    private func sendPhrase() {
        guard canSendPhrase else { return }
        
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        Task {
            var allSuccessful = true
            let targetIds = isAvailableToAll ? availableTargets.map { $0.id } : selectedPlayers.map { $0.id }
            
            // Ensure we have current difficulty analysis before sending
            let finalPhrase = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
            var difficultyAnalysis = currentDifficulty
            
            // If we don't have current difficulty, analyze it now
            if difficultyAnalysis == nil {
                difficultyAnalysis = await networkManager.analyzeDifficulty(phrase: finalPhrase)
            }
            
            // Send phrase to each selected player
            for targetId in targetIds {
                let success = await networkManager.sendPhrase(
                    content: finalPhrase,
                    targetId: targetId,
                    clue: clueText.trimmingCharacters(in: .whitespacesAndNewlines) // Now required, never nil
                )
                
                if !success {
                    allSuccessful = false
                }
            }
            
            await MainActor.run {
                isLoading = false
                
                if allSuccessful {
                    // Directly dismiss the view on success
                    isPresented = false
                } else {
                    errorMessage = "Failed to send phrase to some players. Please try again."
                    showingAlert = true
                }
            }
        }
    }
    
    // Helper method for difficulty color coding
    private func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easy":
            return .green
        case "medium":
            return .orange
        case "hard":
            return .red
        default:
            return .secondary
        }
    }
    
    private func analyzeDifficultyAsync(_ phrase: String) async {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedPhrase.isEmpty else {
            await MainActor.run {
                currentDifficulty = nil
                isAnalyzingDifficulty = false
            }
            return
        }
        
        await MainActor.run {
            isAnalyzingDifficulty = true
        }
        
        let analysis = await networkManager.analyzeDifficulty(phrase: trimmedPhrase)
        
        await MainActor.run {
            isAnalyzingDifficulty = false
            currentDifficulty = analysis
        }
    }
    
    private func selectPlayer(_ player: Player) {
        if !selectedPlayers.contains(where: { $0.id == player.id }) {
            selectedPlayers.append(player)
        }
        playerSearchText = ""
        showingSuggestions = false
        dismissKeyboard()
    }
    
    private func dismissKeyboard() {
        isSearchFieldFocused = false
        isPhraseFieldFocused = false
        isClueFieldFocused = false
    }
    
    private func removePlayer(_ player: Player) {
        selectedPlayers.removeAll { $0.id == player.id }
    }
}

struct PhraseCreationView_Previews: PreviewProvider {
    static var previews: some View {
        PhraseCreationView(isPresented: .constant(true))
    }
}