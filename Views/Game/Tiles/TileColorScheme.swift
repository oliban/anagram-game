//
//  TileColorScheme.swift
//  Anagram Game
//
//  Color scheme system for 3D tile rendering
//

import SwiftUI

// MARK: - Tile Color Scheme System
struct TileColorScheme {
    let topFace: UIColor      // Light color for 3D top surface
    let frontFace: UIColor    // Main visible surface
    let rightFace: UIColor    // Shadow side (darker)
    let strokeColor: UIColor  // Border color
}

extension TileColorScheme {
    // Yellow scheme for letter tiles
    static let yellow = TileColorScheme(
        topFace: UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0),     // Very bright almost white yellow
        frontFace: .systemYellow,                                            // Standard yellow
        rightFace: UIColor(red: 0.2, green: 0.1, blue: 0.0, alpha: 1.0),   // Very dark shadow
        strokeColor: .black
    )
    
    // Green scheme for information tiles
    static let green = TileColorScheme(
        topFace: UIColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),     // Light green
        frontFace: UIColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),   // Medium green
        rightFace: UIColor(red: 0.1, green: 0.4, blue: 0.1, alpha: 1.0),   // Dark green shadow
        strokeColor: .black
    )
    
    // Blue scheme for theme tiles
    static let blue = TileColorScheme(
        topFace: UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),     // Light blue
        frontFace: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),   // Medium blue
        rightFace: UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1.0),   // Dark blue shadow
        strokeColor: .black
    )
    
    // MARK: - Emoji Rarity Color Schemes
    
    // Legendary - Gold (#FFD700)
    static let legendary = TileColorScheme(
        topFace: UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0),     // Light gold
        frontFace: UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0),  // Gold
        rightFace: UIColor(red: 0.6, green: 0.5, blue: 0.0, alpha: 1.0),   // Dark gold shadow
        strokeColor: UIColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0)
    )
    
    // Mythic - Purple (#9B59B6)
    static let mythic = TileColorScheme(
        topFace: UIColor(red: 0.8, green: 0.6, blue: 0.9, alpha: 1.0),     // Light purple
        frontFace: UIColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1.0), // Purple
        rightFace: UIColor(red: 0.4, green: 0.2, blue: 0.5, alpha: 1.0),   // Dark purple shadow
        strokeColor: UIColor(red: 0.5, green: 0.25, blue: 0.6, alpha: 1.0)
    )
    
    // Epic - Blue (#3498DB)
    static let epic = TileColorScheme(
        topFace: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0),     // Light epic blue
        frontFace: UIColor(red: 0.2, green: 0.6, blue: 0.86, alpha: 1.0),  // Epic blue
        rightFace: UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0),   // Dark blue shadow
        strokeColor: UIColor(red: 0.15, green: 0.45, blue: 0.7, alpha: 1.0)
    )
    
    // Rare - Red (#E74C3C)
    static let rare = TileColorScheme(
        topFace: UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1.0),     // Light red
        frontFace: UIColor(red: 0.91, green: 0.3, blue: 0.24, alpha: 1.0), // Red
        rightFace: UIColor(red: 0.6, green: 0.15, blue: 0.1, alpha: 1.0),  // Dark red shadow
        strokeColor: UIColor(red: 0.7, green: 0.2, blue: 0.15, alpha: 1.0)
    )
    
    // Uncommon - Orange (#F39C12)
    static let uncommon = TileColorScheme(
        topFace: UIColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0),     // Light orange
        frontFace: UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0), // Orange
        rightFace: UIColor(red: 0.6, green: 0.35, blue: 0.0, alpha: 1.0),  // Dark orange shadow
        strokeColor: UIColor(red: 0.7, green: 0.4, blue: 0.05, alpha: 1.0)
    )
    
    // Common - Gray (#95A5A6)
    static let common = TileColorScheme(
        topFace: UIColor(red: 0.8, green: 0.85, blue: 0.86, alpha: 1.0),   // Light gray
        frontFace: UIColor(red: 0.58, green: 0.65, blue: 0.65, alpha: 1.0), // Gray
        rightFace: UIColor(red: 0.35, green: 0.4, blue: 0.4, alpha: 1.0),  // Dark gray shadow
        strokeColor: UIColor(red: 0.45, green: 0.5, blue: 0.5, alpha: 1.0)
    )
    
    // MARK: - Rarity Conversion Helper
    static func from(rarity: EmojiRarity) -> TileColorScheme {
        switch rarity {
        case .legendary: return .legendary
        case .mythic: return .mythic
        case .epic: return .epic
        case .rare: return .rare
        case .uncommon: return .uncommon
        case .common: return .common
        }
    }
}