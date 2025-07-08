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
        
        guard let hintStatus = hintStatus,
              let scorePreview = scorePreview else {
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
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                async let statusTask = networkManager.getHintStatus(phraseId: phraseId)
                async let previewTask = networkManager.getPhrasePreview(phraseId: phraseId)
                
                let status = await statusTask
                let preview = await previewTask
                
                await MainActor.run {
                    self.hintStatus = status
                    self.scorePreview = preview?.phrase.scorePreview
                    self.isLoading = false
                }
            }
        }
    }
    
    private func useNextHint() {
        guard let hintStatus = hintStatus,
              let nextLevel = hintStatus.nextHintLevel else {
            return
        }
        
        Task {
            isLoading = true
            
            let hintResponse = await networkManager.useHint(phraseId: phraseId, level: nextLevel)
            
            await MainActor.run {
                if let response = hintResponse {
                    onHintUsed(response.hint.content)
                    
                    self.hintStatus = HintStatus(
                        hintsUsed: hintStatus.hintsUsed + [HintStatus.UsedHint(level: nextLevel, usedAt: Date())],
                        nextHintLevel: response.hint.nextHintScore != nil ? nextLevel + 1 : nil,
                        hintsRemaining: response.hint.hintsRemaining,
                        currentScore: response.hint.currentScore,
                        nextHintScore: response.hint.nextHintScore,
                        canUseNextHint: response.hint.canUseNextHint
                    )
                } else {
                    errorMessage = "Failed to get hint"
                }
                
                isLoading = false
            }
        }
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