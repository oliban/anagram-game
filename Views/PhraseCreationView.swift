import SwiftUI

struct PhraseCreationView: View {
    @Binding var isPresented: Bool
    @StateObject private var networkManager = NetworkManager.shared
    
    @State private var phraseText = ""
    @State private var selectedTargetId = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showingAlert = false
    
    private var wordCount: Int {
        phraseText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }
    
    private var isValidPhrase: Bool {
        let words = wordCount
        return words >= 2 && words <= 6 && !phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var availableTargets: [Player] {
        networkManager.onlinePlayers.filter { $0.id != networkManager.currentPlayer?.id }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Send Custom Phrase")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Create an anagram puzzle for another player")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Phrase input section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Phrase (2-6 words)")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter your phrase...", text: $phraseText, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(3)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        HStack {
                            Text("\(wordCount) words")
                                .font(.caption)
                                .foregroundColor(isValidPhrase ? .green : .secondary)
                            
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
                    }
                }
                
                // Target player selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send to Player")
                        .font(.headline)
                    
                    if availableTargets.isEmpty {
                        Text("No other players online")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        Picker("Select target player", selection: $selectedTargetId) {
                            Text("Choose a player...").tag("")
                            ForEach(availableTargets, id: \.id) { player in
                                Text(player.name).tag(player.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Send button
                    Button(action: sendPhrase) {
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
                        isPresented = false
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
            .padding()
            .navigationBarHidden(true)
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
            // Select first available target if only one exists
            if availableTargets.count == 1 {
                selectedTargetId = availableTargets[0].id
            }
        }
    }
    
    private var canSendPhrase: Bool {
        return isValidPhrase && !selectedTargetId.isEmpty && !availableTargets.isEmpty
    }
    
    private func sendPhrase() {
        guard canSendPhrase else { return }
        
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        Task {
            let success = await networkManager.sendPhrase(
                content: phraseText.trimmingCharacters(in: .whitespacesAndNewlines),
                targetId: selectedTargetId
            )
            
            await MainActor.run {
                isLoading = false
                
                if success {
                    // Directly dismiss the view on success
                    isPresented = false
                } else {
                    errorMessage = "Failed to send phrase. Please try again."
                    showingAlert = true
                }
            }
        }
    }
}

struct PhraseCreationView_Previews: PreviewProvider {
    static var previews: some View {
        PhraseCreationView(isPresented: .constant(true))
    }
}