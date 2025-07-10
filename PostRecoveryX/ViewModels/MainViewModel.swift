import Foundation
import SwiftUI
import SwiftData
import AppKit

@MainActor
class MainViewModel: ObservableObject {
    @Published var scanPath: String = ""
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var scanStatus: String = ""
    @Published var currentSession: ScanSession?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var includeVideos = false
    
    private let fileScanner = FileScanner()
    private let duplicateChecker = DuplicateChecker()
    private let metadataParser = MetadataParser()
    private let folderOrganizer = FolderOrganizer()
    
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for images"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                scanPath = url.path
            }
        }
    }
    
    func startScan() async {
        guard !scanPath.isEmpty else { return }
        guard let modelContext = modelContext else { return }
        
        isScanning = true
        scanProgress = 0.0
        
        let session = ScanSession(scanPath: scanPath)
        modelContext.insert(session)
        currentSession = session
        
        do {
            try modelContext.save()
            
            scanStatus = "Discovering files..."
            let urls = try await fileScanner.scanDirectory(
                at: URL(fileURLWithPath: scanPath),
                includeVideos: includeVideos
            )
            
            session.totalFilesFound = urls.count
            scanStatus = "Found \(urls.count) files. Creating records..."
            
            let files = try await fileScanner.createScannedFiles(
                from: urls,
                in: modelContext
            )
            
            scanStatus = "Extracting metadata..."
            for (index, file) in files.enumerated() {
                try await metadataParser.parseMetadata(for: file)
                session.totalFilesProcessed = index + 1
                scanProgress = Double(index + 1) / Double(files.count) * 0.5
                
                if index % 10 == 0 {
                    try modelContext.save()
                }
            }
            
            scanStatus = "Checking for duplicates..."
            session.status = .processing
            
            let duplicateGroups = try await duplicateChecker.findDuplicates(
                in: files,
                modelContext: modelContext
            )
            
            session.duplicatesFound = duplicateGroups.count
            session.totalSpaceSaved = duplicateGroups.reduce(0) { $0 + $1.potentialSpaceSaved }
            
            scanProgress = 1.0
            session.status = .completed
            session.endDate = Date()
            
            try modelContext.save()
            
            scanStatus = "Scan complete! Found \(duplicateGroups.count) duplicate groups."
            
        } catch {
            session.status = .failed
            session.error = error.localizedDescription
            session.endDate = Date()
            
            errorMessage = error.localizedDescription
            showError = true
            
            try? modelContext.save()
        }
        
        isScanning = false
    }
    
    func cancelScan() async {
        await fileScanner.cancel()
        await duplicateChecker.cancel()
        await folderOrganizer.cancel()
        
        if let session = currentSession {
            session.status = .cancelled
            session.endDate = Date()
            try? modelContext?.save()
        }
        
        isScanning = false
        scanStatus = "Scan cancelled"
    }
}