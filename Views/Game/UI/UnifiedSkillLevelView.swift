//
//  UnifiedSkillLevelView.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from PhysicsGameView.swift during refactoring
//

import SwiftUI

struct UnifiedSkillLevelView: View {
    let levelConfig: LevelConfig
    let totalScore: Int
    let isLevelingUp: Bool
    
    private var currentSkillLevel: SkillLevel {
        levelConfig.getSkillLevel(for: totalScore)
    }
    
    private var progressToNext: Double {
        levelConfig.getProgressToNext(for: totalScore)
    }
    
    private var nextSkillLevel: SkillLevel? {
        levelConfig.getNextSkillLevel(for: totalScore)
    }
    
    private var skillColor: Color {
        Color.skillLevelColor(for: currentSkillLevel.id)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Skill Title Header
            HStack {
                Text("Your skill: \(currentSkillLevel.title.prefix(1).capitalized + currentSkillLevel.title.dropFirst())")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(skillColor)
                    .textCase(.none)
                
                Spacer()
                
                // Level indicator
                Text("L\(currentSkillLevel.id)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(skillColor.opacity(0.9))
                    )
            }
            
            // Progress Bar with Score Inside
            GeometryReader { geometry in
                ZStack {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 24)
                    
                    // Progress fill
                    HStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(skillGradient)
                            .frame(width: geometry.size.width * progressToNext, height: 24)
                            .animation(.easeInOut(duration: 0.4), value: progressToNext)
                        
                        Spacer(minLength: 0)
                    }
                    
                    // Score text overlay
                    HStack {
                        Text("\(totalScore) p")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 1)
                        
                        Spacer()
                        
                        if let nextLevel = nextSkillLevel {
                            Text("→ \(nextLevel.title)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(color: .black, radius: 1)
                        }
                    }
                    .padding(.horizontal, 8)
                    
                    // Glow effect during level up
                    if isLevelingUp {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(skillColor.opacity(0.3))
                            .frame(height: 24)
                            .blur(radius: 4)
                            .animation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true), value: isLevelingUp)
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .stroke(skillColor.opacity(isLevelingUp ? 1.0 : 0.6), lineWidth: isLevelingUp ? 3 : 2)
        )
        .scaleEffect(isLevelingUp ? 1.08 : 1.0)
        .shadow(color: isLevelingUp ? skillColor : .clear, radius: isLevelingUp ? 8 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isLevelingUp)
    }
    
    private var skillGradient: LinearGradient {
        LinearGradient(
            colors: [skillColor.opacity(0.8), skillColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}