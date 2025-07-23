import Foundation
import SwiftData
import UniformTypeIdentifiers

// Thread-safe struct for passing file metadata between threads
private struct FileMetadata {
    let path: String
    let fileName: String
    let fileSize: Int64
    let fileType: String
    let creationDate: Date?
    let modificationDate: Date?
}

enum DataActorError: Error {
    case sessionNotFound
}

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
        fileIDs: [UUID],
        enableVisualMatching: Bool,
        duplicateChecker: DuplicateChecker
    ) async throws -> [DuplicateGroupInfo] {
        // Fetch the files
        let descriptor = FetchDescriptor<ScannedFile>(
            predicate: #Predicate { file in
                fileIDs.contains(file.id)
            }
        )
        let files = try modelContext.fetch(descriptor)
        
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
    
    func createScannedFiles(from urls: [URL], sessionID: UUID) async throws -> [FileInfo] {
        // First get the session
        let sessionDescriptor = FetchDescriptor<ScanSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = try modelContext.fetch(sessionDescriptor).first else {
            throw DataActorError.sessionNotFound
        }
        
        var fileInfos: [FileInfo] = []
        
        // Process URLs in batches to improve performance and memory usage
        let batchSize = PerformanceConfiguration.shared.databaseBatchSize
        let batches = urls.chunked(into: batchSize)
        
        // Save frequency: dynamically based on batch size
        // With larger batches, save less frequently
        let saveFrequency = max(1, 50000 / batchSize) // Save approximately every 50,000 files
        var batchCounter = 0
        
        for batch in batches {
            // Process file resource reading concurrently
            // First extract file metadata in background tasks
            let batchMetadata = await withTaskGroup(of: (URL, FileMetadata?).self) { group in
                for url in batch {
                    group.addTask {
                        do {
                            let resourceValues = try url.resourceValues(forKeys: [
                                .fileSizeKey,
                                .contentTypeKey,
                                .creationDateKey,
                                .contentModificationDateKey
                            ])
                            
                            let fileExtension = url.pathExtension.lowercased()
                            let metadata = FileMetadata(
                                path: url.path,
                                fileName: url.lastPathComponent,
                                fileSize: Int64(resourceValues.fileSize ?? 0),
                                fileType: fileExtension.isEmpty ? "unknown" : fileExtension,
                                creationDate: resourceValues.creationDate,
                                modificationDate: resourceValues.contentModificationDate
                            )
                            
                            return (url, metadata)
                        } catch {
                            return (url, nil)
                        }
                    }
                }
                
                var results: [(URL, FileMetadata?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            
            // Create ScannedFile objects on the actor's thread with proper model context
            for (_, metadata) in batchMetadata {
                if let metadata = metadata {
                    let scannedFile = ScannedFile(
                        path: metadata.path,
                        fileName: metadata.fileName,
                        fileSize: metadata.fileSize,
                        fileType: metadata.fileType
                    )
                    
                    scannedFile.creationDate = metadata.creationDate
                    scannedFile.modificationDate = metadata.modificationDate
                    scannedFile.session = session
                    
                    // Mark as thumbnail if it matches thumbnail criteria
                    scannedFile.isThumbnail = scannedFile.isPotentialThumbnail
                    
                    modelContext.insert(scannedFile)
                    
                    // Create sendable info
                    fileInfos.append(FileInfo(
                        id: scannedFile.id,
                        path: scannedFile.path,
                        fileName: scannedFile.fileName,
                        fileType: scannedFile.fileType
                    ))
                }
            }
            
            batchCounter += 1
            
            // Save less frequently to reduce UI blocking
            if batchCounter % saveFrequency == 0 {
                try modelContext.save()
            }
        }
        
        // Final save for any remaining unsaved data
        if batchCounter % saveFrequency != 0 {
            try modelContext.save()
        }
        
        return fileInfos
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
        
        // Process files in concurrent batches for better performance
        let batchSize = PerformanceConfiguration.shared.metadataParsingBatchSize
        let batches = filesToProcess.chunked(into: batchSize)
        var processedCount = 0
        
        for batch in batches {
            // Process batch concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in batch {
                    group.addTask {
                        try await metadataParser.parseMetadata(for: file)
                    }
                }
                
                // Wait for all tasks in batch to complete
                try await group.waitForAll()
            }
            
            // Update progress after each batch
            processedCount += batch.count
            try await updateSession(id: sessionID, totalFilesProcessed: processedCount)
            
            // Report progress for the last file in batch
            if let lastFile = batch.last {
                await progressCallback(lastFile.fileName, processedCount, totalFiles)
            }
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
        
        let fileIDs = filesToProcess.map { $0.id }
        return try await findDuplicates(
            fileIDs: fileIDs,
            enableVisualMatching: enableVisualMatching,
            duplicateChecker: duplicateChecker
        )
    }
}