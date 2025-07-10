import Foundation
import SwiftData
import CoreImage
import Vision

actor SceneDetector {
    private let imageHasher = ImageHasher()
    private var isCancelled = false
    private var progress: Progress?
    
    // Thresholds for detection
    private let burstTimeThreshold: TimeInterval = 2.0 // seconds
    private let sequenceTimeThreshold: TimeInterval = 30.0 // seconds
    private let eventTimeThreshold: TimeInterval = 3600.0 // 1 hour
    private let visualSimilarityThreshold: Int = 12 // Hamming distance for perceptual hashes
    
    func detectSimilarScenes(in files: [ScannedFile], modelContext: ModelContext) async throws -> [SimilarSceneGroup] {
        isCancelled = false
        progress = Progress(totalUnitCount: Int64(files.count))
        
        // Sort files by creation date
        let sortedFiles = files.sorted { file1, file2 in
            let date1 = file1.originalCreationDate ?? file1.creationDate ?? Date.distantPast
            let date2 = file2.originalCreationDate ?? file2.creationDate ?? Date.distantPast
            return date1 < date2
        }
        
        var sceneGroups: [SimilarSceneGroup] = []
        var processedFiles = Set<UUID>()
        
        // First pass: Detect burst shots (very close timestamps)
        let burstGroups = try await detectBurstShots(in: sortedFiles, processedFiles: &processedFiles)
        sceneGroups.append(contentsOf: burstGroups)
        
        // Second pass: Detect sequences (similar visual content + close timestamps)
        let sequenceGroups = try await detectSequences(in: sortedFiles, processedFiles: &processedFiles)
        sceneGroups.append(contentsOf: sequenceGroups)
        
        // Third pass: Detect events (same location/folder + reasonable time range)
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
        var burstGroups: [SimilarSceneGroup] = []
        var currentBurst: [ScannedFile] = []
        var lastDate: Date?
        
        for file in files {
            if isCancelled { throw SceneDetectorError.cancelled }
            if processedFiles.contains(file.id) { continue }
            
            guard let fileDate = file.originalCreationDate ?? file.creationDate else { continue }
            
            if let lastDate = lastDate {
                let timeDiff = fileDate.timeIntervalSince(lastDate)
                
                if timeDiff <= burstTimeThreshold {
                    // Continue burst
                    currentBurst.append(file)
                } else {
                    // End current burst and start new one
                    if currentBurst.count >= 3 { // Minimum 3 photos for a burst
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
            progress?.completedUnitCount += 1
        }
        
        // Handle last burst
        if currentBurst.count >= 3 {
            let group = createSceneGroup(from: currentBurst, type: .burst)
            burstGroups.append(group)
            processedFiles.formUnion(currentBurst.map { $0.id })
        }
        
        return burstGroups
    }
    
    private func detectSequences(in files: [ScannedFile], processedFiles: inout Set<UUID>) async throws -> [SimilarSceneGroup] {
        var sequenceGroups: [SimilarSceneGroup] = []
        
        // Group unprocessed files by visual similarity
        let unprocessedFiles = files.filter { !processedFiles.contains($0.id) }
        
        for i in 0..<unprocessedFiles.count {
            if isCancelled { throw SceneDetectorError.cancelled }
            
            let file1 = unprocessedFiles[i]
            if processedFiles.contains(file1.id) { continue }
            
            guard let date1 = file1.originalCreationDate ?? file1.creationDate,
                  let hash1 = file1.perceptualHash else { continue }
            
            var sequenceFiles = [file1]
            
            for j in (i+1)..<unprocessedFiles.count {
                let file2 = unprocessedFiles[j]
                if processedFiles.contains(file2.id) { continue }
                
                guard let date2 = file2.originalCreationDate ?? file2.creationDate,
                      let hash2 = file2.perceptualHash else { continue }
                
                let timeDiff = abs(date2.timeIntervalSince(date1))
                let visualDistance = hammingDistance(hash1, hash2)
                
                if timeDiff <= sequenceTimeThreshold && visualDistance <= visualSimilarityThreshold {
                    sequenceFiles.append(file2)
                }
            }
            
            if sequenceFiles.count >= 2 { // Minimum 2 photos for a sequence
                let group = createSceneGroup(from: sequenceFiles, type: .sequence)
                sequenceGroups.append(group)
                processedFiles.formUnion(sequenceFiles.map { $0.id })
            }
        }
        
        return sequenceGroups
    }
    
    private func detectEvents(in files: [ScannedFile], processedFiles: inout Set<UUID>) async throws -> [SimilarSceneGroup] {
        var eventGroups: [SimilarSceneGroup] = []
        
        // Group unprocessed files by folder and time
        let unprocessedFiles = files.filter { !processedFiles.contains($0.id) }
        
        // Group by parent folder
        var folderGroups: [String: [ScannedFile]] = [:]
        for file in unprocessedFiles {
            let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
            folderGroups[folder, default: []].append(file)
        }
        
        // Check each folder group for time-based events
        for (folder, folderFiles) in folderGroups {
            if folderFiles.count < 5 { continue } // Minimum 5 photos for an event
            
            // Sort by date
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
                        // Gap too large, save current event and start new one
                        if eventFiles.count >= 5 {
                            let group = createSceneGroup(from: eventFiles, type: .event)
                            group.locationInfo = URL(fileURLWithPath: folder).lastPathComponent
                            eventGroups.append(group)
                            processedFiles.formUnion(eventFiles.map { $0.id })
                        }
                        eventFiles = [file]
                    }
                } else {
                    eventFiles = [file]
                }
                
                lastDate = fileDate
            }
            
            // Handle last event in folder
            if eventFiles.count >= 5 {
                let group = createSceneGroup(from: eventFiles, type: .event)
                group.locationInfo = URL(fileURLWithPath: folder).lastPathComponent
                eventGroups.append(group)
                processedFiles.formUnion(eventFiles.map { $0.id })
            }
        }
        
        return eventGroups
    }
    
    private func createSceneGroup(from files: [ScannedFile], type: SceneGroupType) -> SimilarSceneGroup {
        let group = SimilarSceneGroup()
        group.groupType = type
        group.files = files
        group.fileCount = files.count
        
        // Calculate time range
        let dates = files.compactMap { $0.originalCreationDate ?? $0.creationDate }
        if let minDate = dates.min(), let maxDate = dates.max() {
            group.timeRange = maxDate.timeIntervalSince(minDate)
        }
        
        // Calculate average perceptual hash if available
        let hashes = files.compactMap { $0.perceptualHash }
        if !hashes.isEmpty {
            // Simple average (not perfect but good enough for grouping)
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
            
            // File size (larger is generally better quality)
            let sizeScore = Double(file.fileSize) / (10 * 1024 * 1024) // Normalize to 10MB
            score += min(sizeScore, 1.0) * 0.3
            
            // Resolution (if available)
            if let width = file.width, let height = file.height {
                let megapixels = Double(width * height) / 1_000_000
                let resolutionScore = min(megapixels / 12.0, 1.0) // Normalize to 12MP
                score += resolutionScore * 0.3
            }
            
            // Has metadata (EXIF data is valuable)
            if file.hasMetadata {
                score += 0.2
            }
            
            // Not a thumbnail
            if !file.isThumbnail {
                score += 0.1
            }
            
            // File name patterns (avoid copies)
            let fileName = file.fileName.lowercased()
            if fileName.contains("copy") || fileName.contains("duplicate") {
                score -= 0.2
            }
            if fileName.contains("original") {
                score += 0.1
            }
            
            scores.append((file: file, score: score))
        }
        
        // Return file with highest score
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
    
    func cancel() {
        isCancelled = true
    }
    
    func currentProgress() -> Progress? {
        progress
    }
}

enum SceneDetectorError: LocalizedError {
    case cancelled
    case noFilesToProcess
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Scene detection was cancelled"
        case .noFilesToProcess:
            return "No files to process for scene detection"
        }
    }
}