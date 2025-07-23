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
    let sharedModelContainer: ModelContainer
    
    init() {
        let schema = Schema([
            ScannedFile.self,
            DuplicateGroup.self,
            OrganizationTask.self,
            ScanSession.self,
            PerformanceData.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If creation fails, try to recover by deleting the store
            print("Failed to create ModelContainer: \(error)")
            print("Attempting to recover by deleting the store...")
            
            let url = modelConfiguration.url
            let fileManager = FileManager.default
            let walUrl = url.appendingPathExtension("wal")
            let shmUrl = url.appendingPathExtension("shm")
            
            try? fileManager.removeItem(at: url)
            try? fileManager.removeItem(at: walUrl)
            try? fileManager.removeItem(at: shmUrl)
            
            print("Cleared corrupted database at: \(url.path)")
            
            // Try once more with a fresh database
            do {
                self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("Successfully created new ModelContainer after cleanup")
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentSize)
    }
}
