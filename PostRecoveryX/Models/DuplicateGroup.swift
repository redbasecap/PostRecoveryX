import Foundation
import SwiftData

@Model
final class DuplicateGroup {
    var id: UUID
    var sha256Hash: String
    var fileSize: Int64
    var fileCount: Int
    @Relationship(deleteRule: .nullify, inverse: \ScannedFile.duplicateGroup)
    var files: [ScannedFile]
    var isResolved: Bool
    var resolutionAction: ResolutionAction?
    var selectedFileID: UUID?
    
    init(sha256Hash: String, fileSize: Int64) {
        self.id = UUID()
        self.sha256Hash = sha256Hash
        self.fileSize = fileSize
        self.fileCount = 0
        self.files = []
        self.isResolved = false
    }
}

enum ResolutionAction: String, Codable, CaseIterable {
    case keepOldest = "Keep Oldest"
    case keepNewest = "Keep Newest"
    case keepLargest = "Keep Largest"
    case keepSelected = "Keep Selected"
    case keepAll = "Keep All"
}

extension DuplicateGroup {
    var oldestFile: ScannedFile? {
        files.min { ($0.originalCreationDate ?? $0.creationDate ?? .distantFuture) < ($1.originalCreationDate ?? $1.creationDate ?? .distantFuture) }
    }
    
    var newestFile: ScannedFile? {
        files.max { ($0.originalCreationDate ?? $0.creationDate ?? .distantPast) < ($1.originalCreationDate ?? $1.creationDate ?? .distantPast) }
    }
    
    var largestFile: ScannedFile? {
        files.max { $0.fileSize < $1.fileSize }
    }
    
    var potentialSpaceSaved: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }
    
    var formattedSpaceSaved: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: potentialSpaceSaved)
    }
}