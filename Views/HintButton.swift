import SwiftUI

struct HintButton: View {
    let phraseId: String
    let onHintUsed: (String) -> Void
    
    @State private var hintStatus: HintStatus?
    @State private var scorePreview: ScorePreview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        Button(action: useNextHint) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                
                Text(buttonText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .disabled(isLoading || !canUseHint)
        .opacity(canUseHint ? 1.0 : 0.6)
        .onAppear {
            loadHintStatus()
        }
        .onChange(of: phraseId) { _, _ in
            loadHintStatus()
        }
    }
    
    private var buttonText: String {
        if isLoading {
            return "Loading..."
        }
        
        guard let hintStatus = hintStatus else {
            return "Hint (? points)"
        }
        
        if !hintStatus.canUseNextHint {
            return "No more hints"
        }
        
        let nextLevel = hintStatus.nextHintLevel ?? 1
        let nextScore = hintStatus.nextHintScore ?? 0
        
        return "Hint \(nextLevel) (\(nextScore) points)"
    }
    
    private var canUseHint: Bool {
        guard let hintStatus = hintStatus else { return false }
        return hintStatus.canUseNextHint && !isLoading
    }
    
    private func loadHintStatus() {
        // Use client-side hint system - no server calls needed
        isLoading = false
    }
    
    private func useNextHint() {
        guard let hintStatus = hintStatus,
              let nextLevel = hintStatus.nextHintLevel else {
            return
        }
        
        // Client-side hint handling - no server calls
        isLoading = true
        
        // Generate hint content based on level
        let hintContent = "Hint \(nextLevel)" // This should be generated based on the phrase
        onHintUsed(hintContent)
        
        // Update hint status locally
        self.hintStatus = HintStatus(
            hintsUsed: hintStatus.hintsUsed + [HintStatus.UsedHint(level: nextLevel, usedAt: Date())],
            nextHintLevel: nextLevel < 3 ? nextLevel + 1 : nil,
            hintsRemaining: 3 - (hintStatus.hintsUsed.count + 1),
            currentScore: hintStatus.currentScore,
            nextHintScore: hintStatus.nextHintScore,
            canUseNextHint: nextLevel < 3
        )
        
        isLoading = false
    }
}

#Preview {
    VStack(spacing: 20) {
        HintButton(phraseId: "test-phrase-id") { hint in
            print("Hint received: \(hint)")
        }
        
        Text("Preview: Hint button with dynamic text")
            .font(.caption)
            .foregroundColor(.gray)
    }
    .padding()
    .background(Color.black)
}