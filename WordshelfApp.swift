//
//  WordshelfApp.swift
//  Wordshelf
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SwiftData
import UIKit

// App Delegate for orientation control
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct WordshelfApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
