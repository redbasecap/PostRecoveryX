import Foundation
import SwiftData
import UniformTypeIdentifiers

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
        
        for batch in batches {
            // Process file resource reading concurrently
            let batchResults = await withTaskGroup(of: (URL, ScannedFile?).self) { group in
                for url in batch {
                    group.addTask {
                        do {
                            let resourceValues = try url.resourceValues(forKeys: [
                                .fileSizeKey,
                                .contentTypeKey,
                                .creationDateKey,
                                .contentModificationDateKey
                            ])
                            
                            let fileSize = Int64(resourceValues.fileSize ?? 0)
                            let scannedFile = ScannedFile(
                                path: url.path,
                                fileName: url.lastPathComponent,
                                fileSize: fileSize,
                                fileType: resourceValues.contentType?.identifier ?? "unknown"
                            )
                            
                            scannedFile.creationDate = resourceValues.creationDate
                            scannedFile.modificationDate = resourceValues.contentModificationDate
                            scannedFile.session = session
                            
                            // Mark as thumbnail if it matches thumbnail criteria
                            scannedFile.isThumbnail = scannedFile.isPotentialThumbnail
                            
                            return (url, scannedFile)
                        } catch {
                            return (url, nil)
                        }
                    }
                }
                
                var results: [(URL, ScannedFile?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            
            // Insert batch results into model context
            for (_, scannedFile) in batchResults {
                if let scannedFile = scannedFile {
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
            
            // Save after each batch to avoid memory buildup
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
    
    func detectSimilarScenes(
        fileIDs: [UUID],
        sceneDetector: SceneDetector
    ) async throws -> [SceneGroupInfo] {
        // Fetch the files
        let descriptor = FetchDescriptor<ScannedFile>(
            predicate: #Predicate { file in
                fileIDs.contains(file.id)
            }
        )
        let files = try modelContext.fetch(descriptor)
        
        // Detect scenes within the actor context
        let sceneGroups = try await detectScenesInContext(files: files)
        
        return sceneGroups.map { group in
            SceneGroupInfo(
                id: group.id,
                fileCount: group.files.count
            )
        }
    }
    
    private func detectScenesInContext(files: [ScannedFile]) async throws -> [SimilarSceneGroup] {
        // Sort files by creation date
        let sortedFiles = files.sorted { file1, file2 in
            let date1 = file1.originalCreationDate ?? file1.creationDate ?? Date.distantPast
            let date2 = file2.originalCreationDate ?? file2.creationDate ?? Date.distantPast
            return date1 < date2
        }
        
        var sceneGroups: [SimilarSceneGroup] = []
        var processedFiles = Set<UUID>()
        
        // Detect burst shots (very close timestamps)
        let burstGroups = try await detectBurstShots(in: sortedFiles, processedFiles: &processedFiles)
        sceneGroups.append(contentsOf: burstGroups)
        
        // Detect sequences (similar visual content + close timestamps)
        let sequenceGroups = try await detectSequences(in: sortedFiles, processedFiles: &processedFiles)
        sceneGroups.append(contentsOf: sequenceGroups)
        
        // Detect events (same location/folder + reasonable time range)
        let eventGroups = try await detectEvents(in: sortedFiles, processedFiles: &processedFiles)
        sceneGroups.append(contentsOf: eventGroups)
        
        // Save all groups to the model context
        for group in sceneGroups {
            modelContext.insert(group)
            
            // Update files with their scene group
            for file in group.files {
                file.similarSceneGroup = group
            }
            
            // Select best photo in each group
            if let bestFile = try await selectBestPhoto(from: group.files) {
                group.bestFileId = bestFile.id
            }
        }
        
        try modelContext.save()
        return sceneGroups
    }
    
    private func detectBurstShots(in files: [ScannedFile], processedFiles: inout Set<UUID>) async throws -> [SimilarSceneGroup] {
        let burstTimeThreshold: TimeInterval = 2.0
        var burstGroups: [SimilarSceneGroup] = []
        var currentBurst: [ScannedFile] = []
        var lastDate: Date?
        
        for file in files {
            if processedFiles.contains(file.id) { continue }
            
            guard let fileDate = file.originalCreationDate ?? file.creationDate else { continue }
            
            if let lastDate = lastDate {
                let timeDiff = fileDate.timeIntervalSince(lastDate)
                
                if timeDiff <= burstTimeThreshold {
                    currentBurst.append(file)
                } else {
                    if currentBurst.count >= 3 {
                        let group = createSceneGroup(from: currentBurst, type: .burst)
                        burstGroups.append(group)
                        processedFiles.formUnion(currentBurst.map { $0.id })
                    }
                    currentBurst = [file]
                }
            } else {
                currentBurst = [file]
            }
            
            lastDate = fileDate
        }
        
        if currentBurst.count >= 3 {
            let group = createSceneGroup(from: currentBurst, type: .burst)
            burstGroups.append(group)
            processedFiles.formUnion(currentBurst.map { $0.id })
        }
        
        return burstGroups
    }
    
    private func detectSequences(in files: [ScannedFile], processedFiles: inout Set<UUID>) async throws -> [SimilarSceneGroup] {
        let sequenceTimeThreshold: TimeInterval = 30.0
        let visualSimilarityThreshold: Int = 12
        var sequenceGroups: [SimilarSceneGroup] = []
        
        let unprocessedFiles = files.filter { !processedFiles.contains($0.id) }
        
        // Process sequence detection in parallel chunks
        let chunkSize = PerformanceConfiguration.shared.sceneDetectionChunkSize
        let chunks = unprocessedFiles.chunked(into: chunkSize)
        
        for chunk in chunks {
            let chunkGroups = await withTaskGroup(of: [SimilarSceneGroup].self) { group in
                group.addTask {
                    var localGroups: [SimilarSceneGroup] = []
                    var localProcessed = Set<UUID>()
                    
                    for i in 0..<chunk.count {
                        let file1 = chunk[i]
                        if localProcessed.contains(file1.id) { continue }
                        
                        guard let date1 = file1.originalCreationDate ?? file1.creationDate,
                              let hash1 = file1.perceptualHash else { continue }
                        
                        var sequenceFiles = [file1]
                        
                        // Check against remaining files in chunk
                        for j in (i+1)..<chunk.count {
                            let file2 = chunk[j]
                            if localProcessed.contains(file2.id) { continue }
                            
                            guard let date2 = file2.originalCreationDate ?? file2.creationDate,
                                  let hash2 = file2.perceptualHash else { continue }
                            
                            let timeDiff = abs(date2.timeIntervalSince(date1))
                            let visualDistance = self.hammingDistance(hash1, hash2)
                            
                            if timeDiff <= sequenceTimeThreshold && visualDistance <= visualSimilarityThreshold {
                                sequenceFiles.append(file2)
                            }
                        }
                        
                        if sequenceFiles.count >= 2 {
                            let group = self.createSceneGroup(from: sequenceFiles, type: .sequence)
                            localGroups.append(group)
                            localProcessed.formUnion(sequenceFiles.map { $0.id })
                        }
                    }
                    
                    return localGroups
                }
                
                var allGroups: [SimilarSceneGroup] = []
                for await chunkResult in group {
                    allGroups.append(contentsOf: chunkResult)
                }
                return allGroups
            }
            
            sequenceGroups.append(contentsOf: chunkGroups)
            // Update global processed set
            for group in chunkGroups {
                processedFiles.formUnion(group.files.map { $0.id })
            }
        }
        
        return sequenceGroups
    }
    
    private func detectEvents(in files: [ScannedFile], processedFiles: inout Set<UUID>) async throws -> [SimilarSceneGroup] {
        let eventTimeThreshold: TimeInterval = 3600.0
        var eventGroups: [SimilarSceneGroup] = []
        
        let unprocessedFiles = files.filter { !processedFiles.contains($0.id) }
        
        // Group files by folder concurrently
        let folderGroups = await withTaskGroup(of: [String: [ScannedFile]].self) { group in
            let chunks = unprocessedFiles.chunked(into: PerformanceConfiguration.shared.sceneDetectionChunkSize)
            
            for chunk in chunks {
                group.addTask {
                    var localFolderGroups: [String: [ScannedFile]] = [:]
                    for file in chunk {
                        let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
                        localFolderGroups[folder, default: []].append(file)
                    }
                    return localFolderGroups
                }
            }
            
            var combined: [String: [ScannedFile]] = [:]
            for await chunkResult in group {
                for (folder, files) in chunkResult {
                    combined[folder, default: []].append(contentsOf: files)
                }
            }
            return combined
        }
        
        // Process each folder's events in parallel
        let folderEventGroups = await withTaskGroup(of: [SimilarSceneGroup].self) { group in
            for (folder, folderFiles) in folderGroups where folderFiles.count >= 5 {
                group.addTask {
                    var localGroups: [SimilarSceneGroup] = []
                    
                    let sorted = folderFiles.sorted { file1, file2 in
                        let date1 = file1.originalCreationDate ?? file1.creationDate ?? Date.distantPast
                        let date2 = file2.originalCreationDate ?? file2.creationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    var eventFiles: [ScannedFile] = []
                    var lastDate: Date?
                    
                    for file in sorted {
                        guard let fileDate = file.originalCreationDate ?? file.creationDate else { continue }
                        
                        if let lastDate = lastDate {
                            let timeDiff = fileDate.timeIntervalSince(lastDate)
                            
                            if timeDiff <= eventTimeThreshold {
                                eventFiles.append(file)
                            } else {
                                if eventFiles.count >= 5 {
                                    let group = self.createSceneGroup(from: eventFiles, type: .event)
                                    group.locationInfo = URL(fileURLWithPath: folder).lastPathComponent
                                    localGroups.append(group)
                                }
                                eventFiles = [file]
                            }
                        } else {
                            eventFiles = [file]
                        }
                        
                        lastDate = fileDate
                    }
                    
                    if eventFiles.count >= 5 {
                        let group = self.createSceneGroup(from: eventFiles, type: .event)
                        group.locationInfo = URL(fileURLWithPath: folder).lastPathComponent
                        localGroups.append(group)
                    }
                    
                    return localGroups
                }
            }
            
            var allGroups: [SimilarSceneGroup] = []
            for await folderResult in group {
                allGroups.append(contentsOf: folderResult)
            }
            return allGroups
        }
        
        eventGroups.append(contentsOf: folderEventGroups)
        
        // Update processed files
        for group in eventGroups {
            processedFiles.formUnion(group.files.map { $0.id })
        }
        
        return eventGroups
    }
    
    private func createSceneGroup(from files: [ScannedFile], type: SceneGroupType) -> SimilarSceneGroup {
        let group = SimilarSceneGroup()
        group.groupType = type
        group.files = files
        group.fileCount = files.count
        
        let dates = files.compactMap { $0.originalCreationDate ?? $0.creationDate }
        if let minDate = dates.min(), let maxDate = dates.max() {
            group.timeRange = maxDate.timeIntervalSince(minDate)
        }
        
        let hashes = files.compactMap { $0.perceptualHash }
        if !hashes.isEmpty {
            let sum = hashes.reduce(0, +)
            group.averagePerceptualHash = sum / UInt64(hashes.count)
        }
        
        return group
    }
    
    private func selectBestPhoto(from files: [ScannedFile]) async throws -> ScannedFile? {
        guard !files.isEmpty else { return nil }
        
        var scores: [(file: ScannedFile, score: Double)] = []
        
        for file in files {
            var score = 0.0
            
            let sizeScore = Double(file.fileSize) / (10 * 1024 * 1024)
            score += min(sizeScore, 1.0) * 0.3
            
            if let width = file.width, let height = file.height {
                let megapixels = Double(width * height) / 1_000_000
                let resolutionScore = min(megapixels / 12.0, 1.0)
                score += resolutionScore * 0.3
            }
            
            if file.hasMetadata {
                score += 0.2
            }
            
            if !file.isThumbnail {
                score += 0.1
            }
            
            let fileName = file.fileName.lowercased()
            if fileName.contains("copy") || fileName.contains("duplicate") {
                score -= 0.2
            }
            if fileName.contains("original") {
                score += 0.1
            }
            
            scores.append((file: file, score: score))
        }
        
        return scores.max(by: { $0.score < $1.score })?.file
    }
    
    private func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        var xor = hash1 ^ hash2
        var count = 0
        while xor != 0 {
            count += 1
            xor &= xor - 1
        }
        return count
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
        
        let fileIDs = filesToProcess.map { $0.id }
        return try await detectSimilarScenes(
            fileIDs: fileIDs,
            sceneDetector: sceneDetector
        )
    }
}