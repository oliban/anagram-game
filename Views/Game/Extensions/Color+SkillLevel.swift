//
//  Color+SkillLevel.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from PhysicsGameView.swift during refactoring
//

import SwiftUI

extension Color {
    static func skillLevelColor(for levelId: Int) -> Color {
        switch levelId {
        case 0: return Color(red: 0.4, green: 0.4, blue: 0.4) // non-existent - dark gray
        case 1: return Color(red: 0.8, green: 0.2, blue: 0.2) // disastrous - dark red
        case 2: return Color(red: 0.9, green: 0.3, blue: 0.3) // wretched - red
        case 3: return Color(red: 1.0, green: 0.4, blue: 0.4) // poor - light red
        case 4: return Color(red: 1.0, green: 0.5, blue: 0.0) // weak - dark orange
        case 5: return Color(red: 1.0, green: 0.6, blue: 0.2) // inadequate - orange
        case 6: return Color(red: 1.0, green: 0.7, blue: 0.3) // passable - light orange
        case 7: return Color(red: 1.0, green: 0.8, blue: 0.0) // solid - gold
        case 8: return Color(red: 1.0, green: 0.9, blue: 0.2) // excellent - yellow
        case 9: return Color(red: 0.9, green: 1.0, blue: 0.3) // formidable - yellow-green
        case 10: return Color(red: 0.6, green: 1.0, blue: 0.4) // outstanding - light green
        case 11: return Color(red: 0.4, green: 0.9, blue: 0.4) // brilliant - green
        case 12: return Color(red: 0.2, green: 0.8, blue: 0.6) // magnificent - teal
        case 13: return Color(red: 0.0, green: 0.7, blue: 0.8) // world class - cyan
        case 14: return Color(red: 0.2, green: 0.6, blue: 1.0) // supernatural - light blue
        case 15: return Color(red: 0.4, green: 0.5, blue: 1.0) // titanic - blue
        case 16: return Color(red: 0.6, green: 0.4, blue: 1.0) // extra-terrestrial - blue-purple
        case 17: return Color(red: 0.7, green: 0.3, blue: 0.9) // mythical - purple
        case 18: return Color(red: 0.8, green: 0.2, blue: 0.8) // magical - magenta
        case 19: return Color(red: 0.9, green: 0.4, blue: 0.7) // utopian - pink-purple
        case 20: return Color(red: 1.0, green: 0.6, blue: 0.8) // divine - pink
        case 21: return Color(red: 1.0, green: 0.8, blue: 0.9) // legendary - light pink
        default: return .white
        }
    }
}