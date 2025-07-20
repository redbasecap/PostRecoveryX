import Foundation
import SwiftData

@ModelActor
actor DataActor {
    func createSession(scanPath: String) -> SessionInfo {
        let session = ScanSession(scanPath: scanPath)
        modelContext.insert(session)
        try? modelContext.save()
        
        return SessionInfo(
            id: session.id,
            scanPath: session.scanPath,
            status: session.status
        )
    }
    
    func getSession(by id: UUID) throws -> SessionInfo? {
        let descriptor = FetchDescriptor<ScanSession>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return nil
        }
        
        return SessionInfo(
            id: session.id,
            scanPath: session.scanPath,
            status: session.status
        )
    }
    
    func getScannedFiles() throws -> [ScannedFile] {
        let descriptor = FetchDescriptor<ScannedFile>(
            sortBy: [SortDescriptor(\.path)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func updateSession(
        id: UUID,
        status: SessionStatus? = nil,
        totalFilesFound: Int? = nil,
        totalFilesProcessed: Int? = nil,
        duplicatesFound: Int? = nil,
        totalSpaceSaved: Int64? = nil,
        error: String? = nil,
        endDate: Date? = nil
    ) throws {
        let descriptor = FetchDescriptor<ScanSession>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let session = try modelContext.fetch(descriptor).first else {
            return
        }
        
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
        
        try modelContext.save()
    }
    
    func findDuplicates(
        files: [ScannedFile],
        enableVisualMatching: Bool,
        duplicateChecker: DuplicateChecker
    ) async throws -> [DuplicateGroupInfo] {
        // Perform the duplicate checking logic
        let duplicateGroups = try await duplicateChecker.findDuplicates(
            in: files,
            modelContext: modelContext,
            enableVisualMatching: enableVisualMatching
        )
        
        // Convert to sendable type
        return duplicateGroups.map { group in
            DuplicateGroupInfo(
                id: group.id,
                fileCount: group.fileCount,
                potentialSpaceSaved: group.potentialSpaceSaved
            )
        }
    }
    
    func createScannedFiles(from urls: [URL]) async throws -> [FileInfo] {
        let fileScanner = FileScanner()
        let scannedFiles = try await fileScanner.createScannedFiles(from: urls)
        
        // Insert all files into the model context
        for file in scannedFiles {
            modelContext.insert(file)
        }
        
        try modelContext.save()
        
        // Return sendable file info
        return scannedFiles.map { file in
            FileInfo(
                id: file.id,
                path: file.path,
                fileName: file.fileName,
                fileType: file.fileType
            )
        }
    }
    
    func parseMetadata(for fileID: UUID, using parser: MetadataParser) async throws {
        let descriptor = FetchDescriptor<ScannedFile>(
            predicate: #Predicate { $0.id == fileID }
        )
        
        guard let file = try modelContext.fetch(descriptor).first else {
            return
        }
        
        try await parser.parseMetadata(for: file)
        try modelContext.save()
    }
    
    func detectSimilarScenes(
        in files: [ScannedFile],
        sceneDetector: SceneDetector
    ) async throws -> [SceneGroupInfo] {
        let sceneGroups = try await sceneDetector.detectSimilarScenes(
            in: files,
            modelContext: modelContext
        )
        
        return sceneGroups.map { group in
            SceneGroupInfo(
                id: group.id,
                fileCount: group.files.count
            )
        }
    }
    
    func clearIncompleteSession(_ sessionID: UUID) async throws {
        let sessionDescriptor = FetchDescriptor<ScanSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        
        guard let session = try modelContext.fetch(sessionDescriptor).first else {
            return
        }
        
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
    
    func deleteDuplicateFile(_ fileID: UUID) async throws {
        let descriptor = FetchDescriptor<ScannedFile>(
            predicate: #Predicate { $0.id == fileID }
        )
        
        guard let file = try modelContext.fetch(descriptor).first else {
            return
        }
        
        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        modelContext.delete(file)
        try modelContext.save()
    }
    
    func deleteDuplicateGroup(_ groupID: UUID) async throws {
        let descriptor = FetchDescriptor<DuplicateGroup>(
            predicate: #Predicate { $0.id == groupID }
        )
        
        guard let group = try modelContext.fetch(descriptor).first else {
            return
        }
        
        modelContext.delete(group)
        try modelContext.save()
    }
    
    func updateDuplicateGroup(_ groupID: UUID, removeFileIDs: [UUID], markResolved: Bool) async throws {
        let groupDescriptor = FetchDescriptor<DuplicateGroup>(
            predicate: #Predicate { $0.id == groupID }
        )
        
        guard let group = try modelContext.fetch(groupDescriptor).first else {
            return
        }
        
        // Remove files by ID
        for fileID in removeFileIDs {
            group.files.removeAll { $0.id == fileID }
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
    
    func getScannedFiles() async throws -> [ScannedFile] {
        let descriptor = FetchDescriptor<ScannedFile>()
        return try modelContext.fetch(descriptor)
    }
    
    func getScannedFiles(for sessionID: UUID) async throws -> [ScannedFile] {
        let descriptor = FetchDescriptor<ScannedFile>(
            predicate: #Predicate { file in
                file.session?.id == sessionID
            }
        )
        return try modelContext.fetch(descriptor)
    }
    
    func getFilteredFileCount(sessionID: UUID, fileTypeFilter: SimpleFileTypeFilter) async throws -> Int {
        let files = try await getScannedFiles(for: sessionID)
        return files.filter { file in
            fileTypeFilter.shouldInclude(fileType: file.fileType)
        }.count
    }
    
    func processFiles(
        sessionID: UUID,
        fileTypeFilter: SimpleFileTypeFilter,
        scanAllFileTypes: Bool,
        metadataParser: MetadataParser,
        progressCallback: @escaping (String, Int, Int) async -> Void
    ) async throws -> Int {
        let files = try await getScannedFiles(for: sessionID)
        
        let filesToProcess: [ScannedFile]
        if scanAllFileTypes && fileTypeFilter.hasSelection {
            filesToProcess = files.filter { file in
                fileTypeFilter.shouldInclude(fileType: file.fileType)
            }
        } else {
            filesToProcess = files
        }
        
        let totalFiles = filesToProcess.count
        
        for (index, file) in filesToProcess.enumerated() {
            try await metadataParser.parseMetadata(for: file)
            try await updateSession(id: sessionID, totalFilesProcessed: index + 1)
            await progressCallback(file.fileName, index + 1, totalFiles)
        }
        
        try modelContext.save()
        return totalFiles
    }
    
    func findDuplicatesForSession(
        sessionID: UUID,
        fileTypeFilter: SimpleFileTypeFilter,
        scanAllFileTypes: Bool,
        enableVisualMatching: Bool,
        duplicateChecker: DuplicateChecker
    ) async throws -> [DuplicateGroupInfo] {
        let files = try await getScannedFiles(for: sessionID)
        
        let filesToProcess: [ScannedFile]
        if scanAllFileTypes && fileTypeFilter.hasSelection {
            filesToProcess = files.filter { file in
                fileTypeFilter.shouldInclude(fileType: file.fileType)
            }
        } else {
            filesToProcess = files
        }
        
        return try await findDuplicates(
            files: filesToProcess,
            enableVisualMatching: enableVisualMatching,
            duplicateChecker: duplicateChecker
        )
    }
    
    func detectSimilarScenesForSession(
        sessionID: UUID,
        fileTypeFilter: SimpleFileTypeFilter,
        scanAllFileTypes: Bool,
        sceneDetector: SceneDetector
    ) async throws -> [SceneGroupInfo] {
        let files = try await getScannedFiles(for: sessionID)
        
        let filesToProcess: [ScannedFile]
        if scanAllFileTypes && fileTypeFilter.hasSelection {
            filesToProcess = files.filter { file in
                fileTypeFilter.shouldInclude(fileType: file.fileType)
            }
        } else {
            filesToProcess = files
        }
        
        return try await detectSimilarScenes(
            in: filesToProcess,
            sceneDetector: sceneDetector
        )
    }
}