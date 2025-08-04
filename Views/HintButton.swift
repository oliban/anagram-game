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
                // Animated lightbulb with glow effect
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(lightbulbColor)
                    .scaleEffect(canUseHint ? 1.0 : 0.8)
                    .shadow(color: lightbulbGlowColor, radius: canUseHint ? 3 : 0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: canUseHint)
                
                Text("Hint")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                // Star rating system showing remaining hints
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < remainingHints ? "star.fill" : "star")
                            .foregroundColor(index < remainingHints ? .yellow : .gray)
                            .font(.system(size: 10))
                            .scaleEffect(index < remainingHints ? 1.0 : 0.7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: remainingHints)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.8))
            .cornerRadius(20)
            .shadow(radius: 4)
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
    
    private var remainingHints: Int {
        guard let hintStatus = hintStatus else { return 3 }
        return hintStatus.hintsRemaining
    }
    
    private var lightbulbColor: Color {
        let remaining = remainingHints
        if remaining == 0 { return .gray }
        if remaining == 1 { return .orange }
        if remaining == 2 { return .yellow }
        return .white // 3 hints remaining
    }
    
    private var lightbulbGlowColor: Color {
        let remaining = remainingHints
        if remaining == 0 { return .clear }
        if remaining == 1 { return .orange }
        if remaining == 2 { return .yellow }
        return .white.opacity(0.8) // 3 hints remaining
    }
    
    private func loadHintStatus() {
        // Initialize hint status if not already set
        if hintStatus == nil {
            hintStatus = HintStatus(
                hintsUsed: [],
                nextHintLevel: 1,
                hintsRemaining: 3,
                currentScore: 0,
                nextHintScore: -5,
                canUseNextHint: true
            )
        }
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