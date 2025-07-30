//
//  HintButtonView.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from PhysicsGameView.swift during refactoring
//

import SwiftUI

struct HintButtonView: View {
    let phraseId: String
    let gameModel: GameModel
    let gameScene: PhysicsGameScene?
    let onHintUsed: (String) -> Void
    
    @State private var hintStatus: HintStatus?
    @State private var scorePreview: ScorePreview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var level3ClueText: String? = nil
    @State private var preloadedTextClue: String = ""
    @State private var showSmokeEffect = false
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        ZStack {
            // Main button or empty state
            Group {
                if let _ = level3ClueText {
                    // After level 3 hint is used, show nothing (complete disappearance)
                    EmptyView()
                } else {
                    Button(action: {
                        useNextHint()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            
                            Text(buttonText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
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
                    .opacity(showSmokeEffect ? 0.0 : (canUseHint ? 1.0 : 0.6))
                    .animation(.easeOut(duration: 0.3), value: showSmokeEffect)
                }
            }
            
            // Smoke puff effect - always available regardless of button state
            if showSmokeEffect {
                ZStack {
                    // Multiple smoke circles for puff effect - more lively!
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(Color.gray.opacity(0.6 + CGFloat.random(in: 0...0.3)))
                            .frame(width: 15 + CGFloat(i) * 4, height: 15 + CGFloat(i) * 4)
                            .offset(
                                x: showSmokeEffect ? CGFloat.random(in: -30...30) : CGFloat.random(in: -2...2),
                                y: showSmokeEffect ? CGFloat.random(in: -30...10) : CGFloat.random(in: -2...2)
                            )
                            .scaleEffect(showSmokeEffect ? CGFloat.random(in: 1.5...3.0) : 0.1)
                            .opacity(showSmokeEffect ? (1.0 - Double(i) * 0.07) : 0.0)
                            .rotationEffect(.degrees(showSmokeEffect ? Double.random(in: -180...180) : 0))
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.05)
                                .delay(Double(i) * 0.03), 
                                value: showSmokeEffect
                            )
                    }
                }
            }
        }
        .onAppear {
            loadHintStatus()
        }
        .onChange(of: phraseId) { _, _ in
            level3ClueText = nil // Reset clue text for new phrase
            showSmokeEffect = false // Reset smoke effect for new phrase
            loadHintStatus()
        }
    }
    
    private var buttonText: String {
        if isLoading {
            return "Loading..."
        }
        
        guard let hintStatus = hintStatus else {
            return "Hint 1"
        }
        
        if !hintStatus.canUseNextHint {
            return "No more hints"
        }
        
        let nextLevel = hintStatus.nextHintLevel ?? 1
        let currentScore = hintStatus.currentScore
        let nextScore = hintStatus.nextHintScore ?? 0
        
        // Calculate point cost (difference between current and next score)
        let pointCost = currentScore - nextScore
        
        
        return "Hint \(nextLevel) (-\(pointCost) p)"
    }
    
    private var canUseHint: Bool {
        // Always allow hints - let the server decide availability
        return !isLoading
    }
    
    private func loadHintStatus() {
        Task {
            isLoading = true
            errorMessage = nil
            
            // Handle local phrases differently
            if phraseId.hasPrefix("local-") {
                await MainActor.run {
                    // Get the actual difficulty score from gameModel
                    let actualScore = gameModel.phraseDifficulty
                    
                    // Create a basic hint status for local phrases with actual scoring
                    // Always start with fresh hints for each game session
                    let nextHintScore = GameModel.applyHintPenalty(baseScore: actualScore, hintsUsed: 1)
                    let newHintStatus = HintStatus(
                        hintsUsed: [],
                        nextHintLevel: 1,
                        hintsRemaining: 3,
                        currentScore: actualScore,
                        nextHintScore: nextHintScore,
                        canUseNextHint: true
                    )
                    self.hintStatus = newHintStatus
                    self.isLoading = false
                }
            } else {
                do {
                    async let statusTask = networkManager.getHintStatus(phraseId: phraseId)
                    async let previewTask = networkManager.getPhrasePreview(phraseId: phraseId)
                    
                    let status = await statusTask
                    let preview = await previewTask
                    
                    await MainActor.run {
                        // Override server hint status to always provide fresh hints for each game
                        if let originalStatus = status {
                            let freshHintStatus = HintStatus(
                                hintsUsed: [],
                                nextHintLevel: 1,
                                hintsRemaining: 3,
                                currentScore: originalStatus.currentScore,
                                nextHintScore: originalStatus.nextHintScore,
                                canUseNextHint: true
                            )
                            self.hintStatus = freshHintStatus
                        } else {
                            self.hintStatus = status
                        }
                        
                        self.scorePreview = preview?.phrase.scorePreview
                        
                        // Store difficulty in GameModel for local score calculation
                        if let difficulty = preview?.phrase.difficultyLevel {
                            self.gameModel.phraseDifficulty = difficulty
                        }
                        
                        self.isLoading = false
                    }
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
            
            // Get text clue from pre-loaded phrase data (no network calls needed!)
            let textClue: String
            if let customPhrase = gameModel.currentCustomPhrase,
               !customPhrase.clue.isEmpty {
                textClue = customPhrase.clue
            } else if let localClue = gameModel.getCurrentLocalClue(),
                      !localClue.isEmpty {
                textClue = localClue
            } else {
                textClue = generateLocalTextHint(sentence: gameModel.currentSentence)
            }
            
            await MainActor.run {
                // Always execute scene methods for visual hints
                guard let scene = gameScene else {
                    isLoading = false
                    return
                }
                
                switch nextLevel {
                case 1:
                    scene.showHint1() // Always highlight shelves
                    gameModel.addHint("Shelves highlighted to show word count")
                case 2:
                    scene.showHint2() // Always highlight first letters
                    gameModel.addHint("First letter tiles highlighted in blue")
                case 3:
                    scene.showHint3() // Always call scene method
                    gameModel.addHint(textClue) // Use the text clue we got
                    // Hide button and show smoke effect for level 3
                    level3ClueText = textClue
                    showSmokeEffect = true
                    scene.spawnMessageTile(message: textClue)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showSmokeEffect = false
                    }
                default:
                    break
                }
                
                // Update hint status with local calculation
                let actualScore = gameModel.phraseDifficulty
                let newScore = calculateLocalScore(currentLevel: nextLevel, originalScore: actualScore)
                let nextHintScore = nextLevel < 3 ? calculateLocalScore(currentLevel: nextLevel + 1, originalScore: actualScore) : nil
                
                let updatedStatus = HintStatus(
                    hintsUsed: hintStatus.hintsUsed + [HintStatus.UsedHint(level: nextLevel, usedAt: Date())],
                    nextHintLevel: nextLevel < 3 ? nextLevel + 1 : nil,
                    hintsRemaining: hintStatus.hintsRemaining - 1,
                    currentScore: newScore,
                    nextHintScore: nextHintScore,
                    canUseNextHint: nextLevel < 3
                )
                self.hintStatus = updatedStatus
                
                // Update UI
                scene.updateScoreTile(hintsUsed: updatedStatus.hintsUsed.count)
                scene.updateLanguageTile()
                
                isLoading = false
            }
        }
    }
    
    private func calculateLocalScore(currentLevel: Int, originalScore: Int) -> Int {
        return ScoreCalculator.shared.applyHintPenalty(baseScore: originalScore, hintsUsed: currentLevel)
    }
    
    private func generateLocalHint(level: Int, sentence: String) -> String {
        guard let scene = gameScene else {
            return "Game scene not ready"
        }
        
        switch level {
        case 1:
            // Hint 1: Highlight shelves (visual hint)
            scene.showHint1()
            return "Shelves highlighted to show word count"
        case 2:
            // Hint 2: Highlight first letter tiles (visual hint)
            scene.showHint2()
            return "First letter tiles highlighted in blue"
        case 3:
            // Hint 3: Show text hint (use clue from local phrases or generate fallback)
            scene.showHint3()
            return generateLocalTextHint(sentence: sentence)
        default:
            return "No hint available"
        }
    }
    
    private func generateLocalTextHint(sentence: String) -> String {
        // First, try to get the clue from the GameModel
        if let clue = gameModel.getCurrentLocalClue() {
            return clue
        }
        
        // Fallback to generic hint if no clue is available
        let words = sentence.components(separatedBy: " ")
        let wordCount = words.count
        let totalLetters = sentence.replacingOccurrences(of: " ", with: "").count
        
        if wordCount == 1 {
            return "A single word with \(totalLetters) letters"
        } else if wordCount == 2 {
            let firstWordLength = words[0].count
            let secondWordLength = words[1].count
            return "Two words: \(firstWordLength) and \(secondWordLength) letters"
        } else if wordCount == 3 {
            let lengths = words.map { $0.count }
            return "Three words with \(lengths[0]), \(lengths[1]), and \(lengths[2]) letters"
        } else {
            return "\(wordCount) words with \(totalLetters) total letters"
        }
    }
}