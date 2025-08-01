//
//  LanguageTile.swift
//  Anagram Game
//
//  Language flag tiles for displaying language information
//

import SwiftUI
import SpriteKit

class LanguageTile: IconTile {
    var currentLanguage: String = "en"
    
    init(language: String, size: CGSize = CGSize(width: 60, height: 60)) {
        super.init(size: size)
        self.currentLanguage = language
        updateFlag(language: language)
    }
    
    func updateFlag(language: String) {
        currentLanguage = language
        let flagImageName = language == "sv" ? "flag_sweden" : "flag_england"
        updateIcon(imageName: flagImageName)
    }
    
    private func getLanguageFlag(for language: String) -> String {
        switch language.lowercased() {
        case "en", "english":
            return "🇺🇸"
        case "sv", "swedish":
            return "🇸🇪"
        case "es", "spanish":
            return "🇪🇸"
        case "fr", "french":
            return "🇫🇷"
        case "de", "german":
            return "🇩🇪"
        default:
            return "🌐"
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}