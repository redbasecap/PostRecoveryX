//
//  PostRecoveryXApp.swift
//  PostRecoveryX
//
//  Created by Nicola Spieser on 10.07.2025.
//

import SwiftUI
import SwiftData

@main
struct PostRecoveryXApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScannedFile.self,
            DuplicateGroup.self,
            OrganizationTask.self,
            ScanSession.self,
            SimilarSceneGroup.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, delete the existing store and create a new one
            print("Migration failed, attempting to delete existing store: \(error)")
            
            let url = modelConfiguration.url
            try? FileManager.default.removeItem(at: url)
            
            // Also remove associated files
            let walUrl = url.appendingPathExtension("wal")
            let shmUrl = url.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walUrl)
            try? FileManager.default.removeItem(at: shmUrl)
            
            // Try creating container again with fresh database
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentSize)
    }
}
