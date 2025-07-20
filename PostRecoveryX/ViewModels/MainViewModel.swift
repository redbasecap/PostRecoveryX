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
    @Published var scanAllFileTypes = true
    @Published var enableVisualMatching = false // Default to OFF to avoid false positives
    @Published var showFileTypeSelection = false
    @Published var fileTypeFilter = FileTypeFilter()
    
    private let fileScanner = FileScanner()
    private let duplicateChecker = DuplicateChecker()
    private let metadataParser = MetadataParser()
    private let folderOrganizer = FolderOrganizer()
    private let sceneDetector = SceneDetector()
    
    private var dataActor: DataActor?
    
    func setModelContext(_ context: ModelContext) {
        let container = context.container
        self.dataActor = DataActor(modelContainer: container)
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
        guard let dataActor = dataActor else { return }
        
        isScanning = true
        scanProgress = 0.0
        
        do {
            // Create session using DataActor
            let session = await dataActor.createSession(scanPath: scanPath)
            currentSession = session
            
            scanStatus = "Discovering files..."
            let urls = try await fileScanner.scanDirectory(
                at: URL(fileURLWithPath: scanPath),
                scanAllTypes: scanAllFileTypes
            )
            
            await dataActor.updateSession(session, totalFilesFound: urls.count)
            scanStatus = "Found \(urls.count) files. Creating records..."
            
            let files = try await dataActor.createScannedFiles(from: urls)
            
            // If scanning all types, show file type selection
            if scanAllFileTypes {
                scanStatus = "Scan complete. Select file types to process..."
                isScanning = false
                showFileTypeSelection = true
                return
            }
            
            // Otherwise, process all files directly
            try await processScannedFiles(files: files, session: session)
            
        } catch {
            if let session = currentSession {
                await dataActor.updateSession(
                    session,
                    status: .failed,
                    error: error.localizedDescription,
                    endDate: Date()
                )
            }
            
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isScanning = false
    }
    
    func cancelScan() async {
        await fileScanner.cancel()
        await duplicateChecker.cancel()
        await folderOrganizer.cancel()
        await sceneDetector.cancel()
        
        if let session = currentSession, let dataActor = dataActor {
            await dataActor.updateSession(
                session,
                status: .cancelled,
                endDate: Date()
            )
        }
        
        isScanning = false
        scanStatus = "Scan cancelled"
    }
    
    func processSelectedFileTypes() async {
        guard let dataActor = dataActor,
              let session = currentSession else { return }
        
        isScanning = true
        showFileTypeSelection = false
        
        do {
            // Get all scanned files and filter by selected types
            let allFiles = try await dataActor.getScannedFiles()
            let filteredFiles = allFiles.filter { file in
                fileTypeFilter.shouldInclude(fileType: file.fileType)
            }
            
            scanStatus = "Processing \(filteredFiles.count) selected files..."
            try await processScannedFiles(files: filteredFiles, session: session)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isScanning = false
    }
    
    private func processScannedFiles(files: [ScannedFile], session: ScanSession) async throws {
        guard let dataActor = dataActor else { return }
        
        scanStatus = "Extracting metadata..."
        for (index, file) in files.enumerated() {
            try await dataActor.parseMetadata(for: file, using: metadataParser)
            await dataActor.updateSession(session, totalFilesProcessed: index + 1)
            scanProgress = Double(index + 1) / Double(files.count) * 0.5
        }
        
        scanStatus = "Checking for duplicates..."
        await dataActor.updateSession(session, status: .processing)
        
        let duplicateGroups = try await dataActor.findDuplicates(
            files: files,
            enableVisualMatching: enableVisualMatching,
            duplicateChecker: duplicateChecker
        )
        
        let totalSpaceSaved = duplicateGroups.reduce(0) { $0 + $1.potentialSpaceSaved }
        await dataActor.updateSession(
            session,
            duplicatesFound: duplicateGroups.count,
            totalSpaceSaved: totalSpaceSaved
        )
        
        // Step 4: Detect similar scenes
        scanStatus = "Detecting similar scenes..."
        scanProgress = 0.9
        
        let sceneGroups = try await dataActor.detectSimilarScenes(
            in: files,
            sceneDetector: sceneDetector
        )
        
        scanProgress = 1.0
        await dataActor.updateSession(session, status: .completed, endDate: Date())
        
        scanStatus = "Processing complete! Found \(duplicateGroups.count) duplicate groups and \(sceneGroups.count) scene groups."
    }
    
    func continueSession(_ session: ScanSession) async {
        currentSession = session
        scanPath = session.scanPath
        
        // Update UI to show session info
        scanStatus = "Continuing previous scan..."
        
        // The duplicate groups and files are already in the database,
        // so the DuplicateManagementView will show them automatically
        
        // Update session to mark it as viewed
        if let dataActor = dataActor {
            await dataActor.updateSession(
                session,
                status: .completed,
                endDate: session.endDate ?? Date()
            )
        }
    }
}