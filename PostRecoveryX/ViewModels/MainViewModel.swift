import Foundation
import SwiftUI
import SwiftData
import AppKit

enum ScanPhase: String {
    case idle = "Ready"
    case discovering = "Discovering Files"
    case creatingRecords = "Creating Records"
    case extractingMetadata = "Extracting Metadata"
    case checkingDuplicates = "Checking for Duplicates"
    case detectingScenes = "Detecting Similar Scenes"
    case complete = "Complete"
}

@MainActor
class MainViewModel: ObservableObject {
    @Published var scanPath: String = ""
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var scanStatus: String = ""
    @Published var currentSessionID: UUID?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var scanAllFileTypes = true
    @Published var enableVisualMatching = false // Default to OFF to avoid false positives
    @Published var showFileTypeSelection = false
    @Published var fileTypeFilter = SimpleFileTypeFilter()
    @Published var discoveredFileTypeCounts: [String: Int] = [:]
    
    // Detailed progress tracking
    @Published var currentFile: String = ""
    @Published var currentPhase: ScanPhase = .idle
    @Published var filesDiscovered: Int = 0
    @Published var filesProcessed: Int = 0
    @Published var totalFiles: Int = 0
    @Published var scanStartTime: Date?
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var progressPercentage: Int = 0
    
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
        scanStartTime = Date()
        progressPercentage = 0
        estimatedTimeRemaining = 0
        
        // Start performance monitoring
        PerformanceMonitor.shared.startMonitoring()
        
        do {
            // Create session using DataActor
            let sessionInfo = await dataActor.createSession(scanPath: scanPath)
            currentSessionID = sessionInfo.id
            
            currentPhase = .discovering
            scanStatus = "Discovering files..."
            filesDiscovered = 0
            
            let urls = try await fileScanner.scanDirectory(
                at: URL(fileURLWithPath: scanPath),
                scanAllTypes: scanAllFileTypes
            ) { [weak self] fileName, count in
                self?.currentFile = fileName
                self?.filesDiscovered = count
                self?.scanStatus = "Discovering files... (\(count) found)"
                self?.updateTimeEstimates()
            }
            
            totalFiles = urls.count
            try await dataActor.updateSession(id: sessionInfo.id, totalFilesFound: urls.count)
            
            currentPhase = .creatingRecords
            scanStatus = "Creating file records..."
            updateTimeEstimates()
            
            let sessionID = sessionInfo.id
            
            // DataActor handles concurrency internally, no need for Task.detached
            let fileInfos = try await dataActor.createScannedFiles(from: urls, sessionID: sessionID)
            
            // If scanning all types, show file type selection
            if scanAllFileTypes {
                // Extract file types from scanned files
                let fileTypes = fileInfos.compactMap { $0.fileType }.reduce(into: Set<String>()) { $0.insert($1) }
                
                // Calculate file type counts
                var typeCounts: [String: Int] = [:]
                for fileInfo in fileInfos {
                    typeCounts[fileInfo.fileType, default: 0] += 1
                }
                
                // Update file type filter with discovered types
                await MainActor.run {
                    self.fileTypeFilter = self.fileTypeFilter.updateDiscoveredTypes(Array(fileTypes))
                    self.discoveredFileTypeCounts = typeCounts
                    self.showFileTypeSelection = true
                }
                
                // Wait for user selection
                return
            } else {
                // Process immediately
                try await processScannedFiles(sessionID: sessionID)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isScanning = false
    }
    
    func processSelectedFileTypes() async {
        guard let sessionID = currentSessionID else { return }
        
        isScanning = true
        scanProgress = 0.0
        scanStartTime = Date()
        progressPercentage = 0
        estimatedTimeRemaining = 0
        
        do {
            // Get file count from the session
            guard let dataActor = dataActor else { return }
            let fileCount = try await dataActor.getFilteredFileCount(
                sessionID: sessionID,
                fileTypeFilter: fileTypeFilter
            )
            
            // Update session with filtered count
            try await dataActor.updateSession(id: sessionID, totalFilesFound: fileCount)
            
            // Store filtered file count for processing
            totalFiles = fileCount
            
            try await processScannedFiles(sessionID: sessionID)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isScanning = false
        // Stop performance monitoring
        PerformanceMonitor.shared.stopMonitoring()
    }
    
    private func processScannedFiles(sessionID: UUID) async throws {
        guard let dataActor = dataActor else { return }
        
        currentPhase = .extractingMetadata
        scanStatus = "Extracting metadata..."
        
        // Process files within the DataActor context
        let processedCount = try await dataActor.processFiles(
            sessionID: sessionID,
            fileTypeFilter: fileTypeFilter,
            scanAllFileTypes: scanAllFileTypes,
            metadataParser: metadataParser
        ) { fileName, processed, total in
            await MainActor.run {
                self.currentFile = fileName
                self.filesProcessed = processed
                self.totalFiles = total
                self.scanStatus = "Extracting metadata... (\(processed)/\(total))"
                self.updateTimeEstimates()
            }
        }
        
        totalFiles = processedCount
        
        currentPhase = .checkingDuplicates
        scanStatus = "Checking for duplicates..."
        updateTimeEstimates()
        try await dataActor.updateSession(id: sessionID, status: .processing)
        
        let duplicateGroupInfos = try await dataActor.findDuplicatesForSession(
            sessionID: sessionID,
            fileTypeFilter: fileTypeFilter,
            scanAllFileTypes: scanAllFileTypes,
            enableVisualMatching: enableVisualMatching,
            duplicateChecker: duplicateChecker
        )
        
        let totalSpaceSaved = duplicateGroupInfos.reduce(0) { $0 + $1.potentialSpaceSaved }
        try await dataActor.updateSession(
            id: sessionID,
            duplicatesFound: duplicateGroupInfos.count,
            totalSpaceSaved: totalSpaceSaved
        )
        
        // Step 4: Detect similar scenes
        currentPhase = .detectingScenes
        scanStatus = "Detecting similar scenes..."
        updateTimeEstimates()
        
        let sceneGroupInfos = try await dataActor.detectSimilarScenesForSession(
            sessionID: sessionID,
            fileTypeFilter: fileTypeFilter,
            scanAllFileTypes: scanAllFileTypes,
            sceneDetector: sceneDetector
        )
        
        currentPhase = .complete
        updateTimeEstimates()
        try await dataActor.updateSession(id: sessionID, status: .completed, endDate: Date())
        
        scanStatus = "Processing complete! Found \(duplicateGroupInfos.count) duplicate groups and \(sceneGroupInfos.count) scene groups."
    }
    
    private func updateTimeEstimates() {
        guard let startTime = scanStartTime, totalFiles > 0 else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Calculate overall progress based on phase and file progress
        var overallProgress: Double = 0
        
        switch currentPhase {
        case .idle:
            overallProgress = 0
        case .discovering:
            overallProgress = 0.1 // Discovery is about 10% of total time
        case .creatingRecords:
            overallProgress = 0.15 // Creating records is quick, about 5%
        case .extractingMetadata:
            // Metadata extraction is 40% of total time
            let metadataProgress = filesProcessed > 0 ? Double(filesProcessed) / Double(totalFiles) : 0
            overallProgress = 0.15 + (metadataProgress * 0.4)
        case .checkingDuplicates:
            overallProgress = 0.55 // Duplicate checking is about 30% after metadata
        case .detectingScenes:
            overallProgress = 0.85 // Scene detection is about 15%
        case .complete:
            overallProgress = 1.0
        }
        
        // Update percentage
        progressPercentage = Int(overallProgress * 100)
        
        // Calculate time remaining
        if overallProgress > 0 && overallProgress < 1.0 {
            let estimatedTotal = elapsed / overallProgress
            estimatedTimeRemaining = max(0, estimatedTotal - elapsed)
        } else {
            estimatedTimeRemaining = 0
        }
        
        // Update progress bar
        scanProgress = overallProgress
        
        // Update performance monitor time estimate
        _ = PerformanceMonitor.shared.estimateTimeRemaining(totalFiles: totalFiles)
    }
    
    
    func cancelScan() async {
        // Cancel operations
        await fileScanner.cancel()
        await duplicateChecker.cancel()
        
        // Update session status
        if let sessionID = currentSessionID, let dataActor = dataActor {
            try? await dataActor.updateSession(id: sessionID, status: .cancelled, endDate: Date())
        }
        
        // Reset UI
        isScanning = false
        scanProgress = 0.0
        currentPhase = .idle
        scanStatus = "Scan cancelled"
        
        // Stop performance monitoring
        PerformanceMonitor.shared.stopMonitoring()
    }
}

extension MainViewModel {
    var currentSession: ScanSession? {
        // This would need to be implemented to fetch the current session
        // For now, returning nil as it requires async context
        nil
    }
}