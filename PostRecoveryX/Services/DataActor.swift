import Foundation
import SwiftData

@ModelActor
actor DataActor {
    func createSession(scanPath: String) -> ScanSession {
        let session = ScanSession(scanPath: scanPath)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
    
    func getScannedFiles() throws -> [ScannedFile] {
        let descriptor = FetchDescriptor<ScannedFile>(
            sortBy: [SortDescriptor(\.path)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func updateSession(
        _ session: ScanSession,
        status: SessionStatus? = nil,
        totalFilesFound: Int? = nil,
        totalFilesProcessed: Int? = nil,
        duplicatesFound: Int? = nil,
        totalSpaceSaved: Int64? = nil,
        error: String? = nil,
        endDate: Date? = nil
    ) {
        if let status = status {
            session.status = status
        }
        if let totalFilesFound = totalFilesFound {
            session.totalFilesFound = totalFilesFound
        }
        if let totalFilesProcessed = totalFilesProcessed {
            session.totalFilesProcessed = totalFilesProcessed
        }
        if let duplicatesFound = duplicatesFound {
            session.duplicatesFound = duplicatesFound
        }
        if let totalSpaceSaved = totalSpaceSaved {
            session.totalSpaceSaved = totalSpaceSaved
        }
        if let error = error {
            session.error = error
        }
        if let endDate = endDate {
            session.endDate = endDate
        }
        
        try? modelContext.save()
    }
    
    func findDuplicates(
        files: [ScannedFile],
        enableVisualMatching: Bool,
        duplicateChecker: DuplicateChecker
    ) async throws -> [DuplicateGroup] {
        // Perform the duplicate checking logic
        let duplicateGroups = try await duplicateChecker.findDuplicates(
            in: files,
            modelContext: modelContext,
            enableVisualMatching: enableVisualMatching
        )
        
        return duplicateGroups
    }
    
    func createScannedFiles(from urls: [URL]) async throws -> [ScannedFile] {
        let fileScanner = FileScanner()
        let scannedFiles = try await fileScanner.createScannedFiles(from: urls)
        
        // Insert all files into the model context
        for file in scannedFiles {
            modelContext.insert(file)
        }
        
        try modelContext.save()
        return scannedFiles
    }
    
    func parseMetadata(for file: ScannedFile, using parser: MetadataParser) async throws {
        try await parser.parseMetadata(for: file)
        try modelContext.save()
    }
    
    func detectSimilarScenes(
        in files: [ScannedFile],
        sceneDetector: SceneDetector
    ) async throws -> [SimilarSceneGroup] {
        let sceneGroups = try await sceneDetector.detectSimilarScenes(
            in: files,
            modelContext: modelContext
        )
        
        return sceneGroups
    }
    
    func clearIncompleteSession(_ session: ScanSession) async throws {
        // Mark session as cancelled
        session.status = .cancelled
        session.endDate = Date()
        
        // Clear associated duplicate groups
        let duplicateGroups = try modelContext.fetch(FetchDescriptor<DuplicateGroup>())
        for group in duplicateGroups {
            modelContext.delete(group)
        }
        
        // Clear scanned files from this session
        let files = try modelContext.fetch(FetchDescriptor<ScannedFile>())
        for file in files {
            if file.duplicateGroup != nil {
                modelContext.delete(file)
            }
        }
        
        try modelContext.save()
    }
    
    func deleteDuplicateFile(_ file: ScannedFile) async throws {
        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        modelContext.delete(file)
        try modelContext.save()
    }
    
    func deleteDuplicateGroup(_ group: DuplicateGroup) async throws {
        modelContext.delete(group)
        try modelContext.save()
    }
    
    func updateDuplicateGroup(_ group: DuplicateGroup, removeFiles: [ScannedFile], markResolved: Bool) async throws {
        for file in removeFiles {
            group.files.removeAll { $0.id == file.id }
        }
        group.fileCount = group.files.count
        if markResolved {
            group.isResolved = true
        }
        
        // Remove group if only one file remains
        if group.files.count <= 1 {
            modelContext.delete(group)
        }
        
        try modelContext.save()
    }
}