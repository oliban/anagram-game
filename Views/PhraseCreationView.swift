import SwiftUI
import Foundation

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
    @State private var selectedLanguage: String = "en" // Default to English
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
                    
                    Text("Create an anagram puzzle for other players to solve")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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
                        TextField("Enter a helpful clue (min 10 characters)...", text: $clueText, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(1...3)
                            .frame(minHeight: 44)
                            .autocapitalization(.sentences)
                            .focused($isClueFieldFocused)
                            .foregroundColor(.primary)
                            .accentColor(.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        clueText.count < 10 && !clueText.isEmpty ? Color.orange : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("This clue will be revealed when the player uses Hint 3")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                
                                Text("All clues require minimum 10 characters")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(clueText.count)/10")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(clueText.count >= 10 ? .green : (clueText.isEmpty ? .secondary : .orange))
                        }
                    }
                }
                
                // Language selection section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Language")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        // English option
                        Button(action: {
                            selectedLanguage = "en"
                        }) {
                            HStack(spacing: 8) {
                                Image("flag_england")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 16)
                                
                                Text("English")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedLanguage == "en" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedLanguage == "en" ? Color.blue.opacity(0.2) : Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedLanguage == "en" ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Swedish option
                        Button(action: {
                            selectedLanguage = "sv"
                        }) {
                            HStack(spacing: 8) {
                                Image("flag_sweden")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 16)
                                
                                Text("Svenska")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedLanguage == "sv" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedLanguage == "sv" ? Color.blue.opacity(0.2) : Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedLanguage == "sv" ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text("Select the language for this phrase. This will be displayed as a flag icon during gameplay.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                
                // Player availability section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send to Players")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Choose where your puzzle will be delivered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Available to all players checkbox
                    Button(action: {
                        isAvailableToAll.toggle()
                    }) {
                        HStack {
                            Image(systemName: isAvailableToAll ? "checkmark.square.fill" : "square")
                                .foregroundColor(isAvailableToAll ? .blue : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add to global phrase pool")
                                    .foregroundColor(.primary)
                                Text("Available for any player to pick up")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                    } else {
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Type at least 2 characters to search and select players who will receive your puzzle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Text("Targeting specific players creates a challenge for them to solve. They'll be notified and can start playing immediately.")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
            // Auto-detect language based on Swedish characters
            detectLanguage(from: newValue)
            
            // Cancel existing timer
            debounceTimer?.invalidate()
            
            // Clear state if phrase is invalid
            if !isValidPhraseForDifficulty {
                currentDifficulty = nil
                isAnalyzingDifficulty = false
                return
            }
            
            // Use client-side scoring for immediate feedback
            analyzeDifficultyClientSide(newValue)
        }
        .onChange(of: playerSearchText) { _, newValue in
            // Show suggestions when typing, hide when empty
            showingSuggestions = !newValue.isEmpty
        }
    }
    
    private var canSendPhrase: Bool {
        let hasValidTargets = !availableTargets.isEmpty && (isAvailableToAll || !selectedPlayers.isEmpty)
        let hasValidClue = clueText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
        
        return isValidPhrase && hasValidTargets && hasValidClue
    }
    
    private func sendPhrase() {
        guard canSendPhrase else { return }
        
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        Task {
            var allSuccessful = true
            let finalPhrase = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
            var difficultyAnalysis = currentDifficulty
            
            // If we don't have current difficulty, analyze it now
            if difficultyAnalysis == nil {
                difficultyAnalysis = await networkManager.analyzeDifficulty(phrase: finalPhrase)
            }
            
            // Create single phrase with multiple delivery methods
            let targetIds = selectedPlayers.map { $0.id }
            
            let success = await networkManager.createEnhancedPhrase(
                content: finalPhrase,
                hint: clueText.trimmingCharacters(in: .whitespacesAndNewlines),
                targetIds: targetIds,
                isGlobal: isAvailableToAll,
                language: selectedLanguage
            )
            
            if !success {
                allSuccessful = false
            }
            
            await MainActor.run {
                isLoading = false
                
                if allSuccessful {
                    // Create appropriate success message
                    var actions: [String] = []
                    if isAvailableToAll {
                        actions.append("added to global pool")
                    }
                    if !selectedPlayers.isEmpty {
                        actions.append("sent to \(selectedPlayers.count) player\(selectedPlayers.count == 1 ? "" : "s")")
                    }
                    
                    successMessage = "Phrase " + actions.joined(separator: " and ") + " successfully!"
                    
                    // Dismiss after a brief delay to show success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isPresented = false
                    }
                } else {
                    var errorActions: [String] = []
                    if isAvailableToAll {
                        errorActions.append("add to global pool")
                    }
                    if !selectedPlayers.isEmpty {
                        errorActions.append("send to selected players")
                    }
                    
                    errorMessage = "Failed to " + errorActions.joined(separator: " and ") + ". Please try again."
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
    
    private func analyzeDifficultyClientSide(_ phrase: String) {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedPhrase.isEmpty else {
            currentDifficulty = nil
            isAnalyzingDifficulty = false
            return
        }
        
        // Client-side analysis for immediate feedback (no network calls)
        let analysis = NetworkManager.analyzeDifficultyClientSide(
            phrase: trimmedPhrase,
            language: selectedLanguage
        )
        
        currentDifficulty = analysis
        isAnalyzingDifficulty = false
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
    
    private func detectLanguage(from text: String) {
        let cleanText = text.lowercased()
        
        // Detect Swedish characters (å, ä, ö)
        if cleanText.range(of: "[åäö]", options: .regularExpression) != nil {
            if selectedLanguage != "sv" {
                selectedLanguage = "sv"
            }
        } else if !cleanText.isEmpty && selectedLanguage == "sv" {
            // If text doesn't contain Swedish characters but language was Swedish, reset to English
            selectedLanguage = "en"
        }
    }
}

struct PhraseCreationView_Previews: PreviewProvider {
    static var previews: some View {
        PhraseCreationView(isPresented: .constant(true))
    }
}