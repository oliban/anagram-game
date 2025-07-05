//
//  Item.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
