import SwiftUI

struct PlayerRegistrationView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @Binding var isPresented: Bool
    @State private var playerName: String = ""
    @State private var isRegistering: Bool = false
    @State private var errorMessage: String? = nil
    @State private var nameSuggestions: [String] = []
    @State private var showSuggestions: Bool = false
    
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
                    
                    // Version number
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Server URL display for debugging
                    Text("Server: \(AppConfig.baseURL)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
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
                                if canRegister {
                                    registerPlayer()
                                }
                            }
                        
                        // Validation feedback
                        if !playerName.isEmpty {
                            HStack {
                                Image(systemName: isValidFormat ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(isValidFormat ? .green : .red)
                                
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundColor(isValidFormat ? .green : .red)
                            }
                        }
                        
                        // Error message display (inline instead of popup)
                        if let errorMessage = errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                // Additional debug info
                                Text("Debug: Attempting connection to:")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text(AppConfig.baseURL)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Name suggestions section
                    if showSuggestions && !nameSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name suggestions:")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            ForEach(nameSuggestions, id: \.self) { suggestion in
                                Button(action: {
                                    playerName = suggestion
                                    showSuggestions = false
                                    nameSuggestions = []
                                }) {
                                    HStack {
                                        Text(suggestion)
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.top, 8)
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
    }
    
    // MARK: - Computed Properties
    
    private var isValidFormat: Bool {
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
        } else if !isValidFormat {
            return "Only letters, numbers, spaces, hyphens, and underscores allowed"
        } else {
            return "Valid name format"
        }
    }
    
    private var canRegister: Bool {
        return isValidFormat && !isRegistering
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
            print("🔧 DEBUG: Testing connection to server...")
            let connectionResult = await networkManager.testConnection()
            print("🔧 DEBUG: Connection test result: \(connectionResult)")
            
            guard case .success = connectionResult else {
                let errorMsg: String
                switch connectionResult {
                case .failure(let connectionError):
                    errorMsg = "Connection test failed: \(connectionError)"
                default:
                    errorMsg = "Cannot connect to server. Please check your connection. Result: \(connectionResult)"
                }
                
                await MainActor.run {
                    isRegistering = false
                    errorMessage = errorMsg
                }
                return
            }
            
            // Register player (this will also establish WebSocket connection)
            let result = await networkManager.registerPlayer(name: trimmedName)
            
            await MainActor.run {
                isRegistering = false
                
                switch result {
                case .success:
                    // Store player name locally
                    UserDefaults.standard.set(trimmedName, forKey: "playerName")
                    // Wait briefly to ensure connection is stable before closing
                    Task {
                        try? await Task.sleep(nanoseconds: AppConfig.registrationStabilizationDelay)
                        await MainActor.run {
                            isPresented = false
                        }
                    }
                    
                case .nameConflict(let suggestions):
                    // Show name suggestions
                    nameSuggestions = suggestions
                    showSuggestions = true
                    errorMessage = "Name '\(trimmedName)' is already taken by another device. Try one of the suggestions below:"
                    
                case .failure(let message):
                    // Show error message
                    errorMessage = message
                    // Clear any previous suggestions
                    showSuggestions = false
                    nameSuggestions = []
                }
            }
        }
    }
}

#Preview {
    PlayerRegistrationView(isPresented: .constant(true))
}