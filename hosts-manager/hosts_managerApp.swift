//
//  hosts_managerApp.swift
//  hosts-manager
//
//  Created by Breeze on 2026-08-19.
//

import SwiftUI
import CoreData

@main
struct hosts_managerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
