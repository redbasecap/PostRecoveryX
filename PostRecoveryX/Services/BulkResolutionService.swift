import Foundation
import SwiftData

actor BulkResolutionService {
    private let container: ModelContainer
    
    enum BulkResolutionStrategy: String, CaseIterable {
        case keepLargest = "Keep Largest Files"
        case keepOldest = "Keep Oldest Files"
        case keepNewest = "Keep Newest Files"
        case keepHighestResolution = "Keep Highest Resolution"
        
        var description: String {
            switch self {
            case .keepLargest:
                return "Keep the largest file from each duplicate group"
            case .keepOldest:
                return "Keep the oldest file from each duplicate group"
            case .keepNewest:
                return "Keep the newest file from each duplicate group"
            case .keepHighestResolution:
                return "Keep the file with highest resolution from each duplicate group"
            }
        }
    }
    
    struct ProgressInfo: Sendable {
        let processed: Int
        let total: Int
        let currentGroup: String?
        var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(processed) / Double(total) * 100
        }
    }
    
    init(container: ModelContainer) {
        self.container = container
    }
    
    func resolveAllDuplicates(
        using strategy: BulkResolutionStrategy,
        progressHandler: @escaping (ProgressInfo) -> Void
    ) async throws -> (resolved: Int, spaceSaved: Int64) {
        let context = ModelContext(container)
        
        // Fetch all unresolved duplicate groups
        var descriptor = FetchDescriptor<DuplicateGroup>()
        descriptor.predicate = #Predicate { group in
            !group.isResolved && group.files.count > 1
        }
        
        let groups = try context.fetch(descriptor)
        let total = groups.count
        var resolved = 0
        var totalSpaceSaved: Int64 = 0
        
        for (index, group) in groups.enumerated() {
            // Send progress update
            await MainActor.run {
                progressHandler(ProgressInfo(
                    processed: index,
                    total: total,
                    currentGroup: "Processing group \(index + 1) of \(total)"
                ))
            }
            
            // Determine which file to keep based on strategy
            let fileToKeep: ScannedFile? = switch strategy {
            case .keepLargest:
                group.largestFile
            case .keepOldest:
                group.oldestFile
            case .keepNewest:
                group.newestFile
            case .keepHighestResolution:
                group.highestResolutionFile
            }
            
            // Apply resolution
            if let fileToKeep = fileToKeep {
                group.selectedFileID = fileToKeep.id
                group.resolutionAction = switch strategy {
                case .keepLargest:
                    .keepLargest
                case .keepOldest:
                    .keepOldest
                case .keepNewest:
                    .keepNewest
                case .keepHighestResolution:
                    .keepBestQuality // Using best quality as proxy for highest resolution
                }
                group.isResolved = true
                resolved += 1
                totalSpaceSaved += group.potentialSpaceSaved
            }
            
            // Save periodically to avoid memory issues
            if index % 100 == 0 {
                try context.save()
            }
        }
        
        // Final save
        try context.save()
        
        // Send final progress update
        await MainActor.run {
            progressHandler(ProgressInfo(
                processed: total,
                total: total,
                currentGroup: "Completed"
            ))
        }
        
        return (resolved, totalSpaceSaved)
    }
    
    func undoAllResolutions() async throws -> Int {
        let context = ModelContext(container)
        
        // Fetch all resolved duplicate groups
        var descriptor = FetchDescriptor<DuplicateGroup>()
        descriptor.predicate = #Predicate { group in
            group.isResolved
        }
        
        let groups = try context.fetch(descriptor)
        var undoneCount = 0
        
        for group in groups {
            group.isResolved = false
            group.resolutionAction = nil
            group.selectedFileID = nil
            undoneCount += 1
        }
        
        try context.save()
        return undoneCount
    }
    
    func applyResolutions(deleteFiles: Bool = false) async throws -> (processed: Int, errors: [String]) {
        let context = ModelContext(container)
        
        // Fetch all resolved duplicate groups
        var descriptor = FetchDescriptor<DuplicateGroup>()
        descriptor.predicate = #Predicate { group in
            group.isResolved
        }
        
        let groups = try context.fetch(descriptor)
        var processed = 0
        var errors: [String] = []
        
        for group in groups {
            guard let action = group.resolutionAction else { continue }
            
            // Determine which files to delete based on the resolution action
            var filesToDelete: [ScannedFile] = []
            
            switch action {
            case .keepOldest:
                if let fileToKeep = group.oldestFile {
                    filesToDelete = group.files.filter { $0.id != fileToKeep.id }
                }
            case .keepNewest:
                if let fileToKeep = group.newestFile {
                    filesToDelete = group.files.filter { $0.id != fileToKeep.id }
                }
            case .keepLargest:
                if let fileToKeep = group.largestFile {
                    filesToDelete = group.files.filter { $0.id != fileToKeep.id }
                }
            case .keepBestQuality:
                if let fileToKeep = group.bestQualityFile {
                    filesToDelete = group.files.filter { $0.id != fileToKeep.id }
                }
            case .keepSelected:
                if let selectedID = group.selectedFileID {
                    filesToDelete = group.files.filter { $0.id != selectedID }
                }
            case .keepAll:
                filesToDelete = []
            case .deleteAll:
                filesToDelete = group.files
            }
            
            // Actually delete the files if requested
            if deleteFiles && !filesToDelete.isEmpty {
                for file in filesToDelete {
                    do {
                        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                        context.delete(file)
                        processed += 1
                    } catch {
                        errors.append("Failed to delete \(file.fileName): \(error.localizedDescription)")
                    }
                }
            } else {
                // Just mark as processed without deleting
                processed += filesToDelete.count
            }
        }
        
        try context.save()
        return (processed, errors)
    }
    
    func getStatistics() async throws -> (
        totalGroups: Int,
        resolvedGroups: Int,
        totalDuplicates: Int,
        potentialSpaceSaved: Int64
    ) {
        let context = ModelContext(container)
        
        // Fetch all duplicate groups
        let allGroups = try context.fetch(FetchDescriptor<DuplicateGroup>())
        let resolvedGroups = allGroups.filter { $0.isResolved }
        
        let totalDuplicates = allGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }
        let potentialSpaceSaved = allGroups.reduce(0) { $0 + $1.potentialSpaceSaved }
        
        return (
            totalGroups: allGroups.count,
            resolvedGroups: resolvedGroups.count,
            totalDuplicates: totalDuplicates,
            potentialSpaceSaved: potentialSpaceSaved
        )
    }
}