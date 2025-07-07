import SwiftUI

struct PlayerRegistrationView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @Binding var isPresented: Bool
    @State private var playerName: String = ""
    @State private var isRegistering: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Join Game")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Enter your player name to start playing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Registration Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Player Name")
                            .font(.headline)
                        
                        TextField("Enter your name", text: $playerName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .onSubmit {
                                if isValidName && networkManager.isConnected {
                                    registerPlayer()
                                }
                            }
                        
                        // Validation feedback
                        if !playerName.isEmpty {
                            HStack {
                                Image(systemName: isValidName ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(isValidName ? .green : .red)
                                
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundColor(isValidName ? .green : .red)
                            }
                        }
                    }
                    
                    // Register Button
                    Button(action: registerPlayer) {
                        HStack {
                            if isRegistering {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            
                            Text(isRegistering ? "Registering..." : "Join Game")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(buttonBackgroundColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canRegister)
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .alert("Registration Failed", isPresented: $showError) {
            Button("OK") {
                showError = false
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidName: Bool {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 && trimmed.count <= 20 else { return false }
        
        let validPattern = "^[a-zA-Z0-9\\s\\-_]+$"
        let regex = try? NSRegularExpression(pattern: validPattern)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }
    
    private var validationMessage: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmed.count > 20 {
            return "Name must be 20 characters or less"
        } else if !isValidName {
            return "Only letters, numbers, spaces, hyphens, and underscores allowed"
        } else {
            return "Valid name"
        }
    }
    
    private var canRegister: Bool {
        return isValidName && !isRegistering
    }
    
    private var buttonBackgroundColor: Color {
        if canRegister {
            return .blue
        } else {
            return .gray
        }
    }
    
    // MARK: - Actions
    
    private func registerPlayer() {
        guard canRegister else { return }
        
        isRegistering = true
        errorMessage = nil
        
        Task {
            let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // First, test connection to server
            let connectionResult = await networkManager.testConnection()
            
            guard case .success = connectionResult else {
                await MainActor.run {
                    isRegistering = false
                    errorMessage = "Cannot connect to server. Please check your connection."
                    showError = true
                }
                return
            }
            
            // Register player (this will also establish WebSocket connection)
            let success = await networkManager.registerPlayer(name: trimmedName)
            
            await MainActor.run {
                isRegistering = false
                
                if success {
                    // Store player name locally
                    UserDefaults.standard.set(trimmedName, forKey: "playerName")
                } else {
                    errorMessage = "Registration failed. Please try again."
                    showError = true
                }
            }
            
            if success {
                // Wait briefly to ensure connection is stable before closing
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    PlayerRegistrationView(isPresented: .constant(true))
}