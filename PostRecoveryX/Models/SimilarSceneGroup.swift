import Foundation
import SwiftData

@Model
final class SimilarSceneGroup {
    var id: UUID
    var groupType: SceneGroupType
    var files: [ScannedFile]
    var fileCount: Int
    var bestFileId: UUID?
    var createdDate: Date
    var timeRange: TimeInterval // Duration between first and last photo
    var averagePerceptualHash: UInt64?
    var locationInfo: String? // GPS or folder-based location
    
    init() {
        self.id = UUID()
        self.groupType = .unknown
        self.files = []
        self.fileCount = 0
        self.createdDate = Date()
        self.timeRange = 0
    }
}

enum SceneGroupType: String, Codable {
    case burst = "Burst"
    case sequence = "Sequence"
    case event = "Event"
    case location = "Location"
    case unknown = "Unknown"
}

extension SimilarSceneGroup {
    var formattedTimeRange: String {
        if timeRange < 1 {
            return "< 1 second"
        } else if timeRange < 60 {
            return "\(Int(timeRange)) seconds"
        } else if timeRange < 3600 {
            return "\(Int(timeRange / 60)) minutes"
        } else if timeRange < 86400 {
            return String(format: "%.1f hours", timeRange / 3600)
        } else {
            return String(format: "%.1f days", timeRange / 86400)
        }
    }
    
    var dateRange: String? {
        guard let firstDate = files.first?.originalCreationDate ?? files.first?.creationDate,
              let lastDate = files.last?.originalCreationDate ?? files.last?.creationDate else {
            return nil
        }
        
        if Calendar.current.isDate(firstDate, inSameDayAs: lastDate) {
            return firstDate.formatted(date: .abbreviated, time: .omitted)
        } else {
            return "\(firstDate.formatted(date: .abbreviated, time: .omitted)) - \(lastDate.formatted(date: .abbreviated, time: .omitted))"
        }
    }
    
    var bestFile: ScannedFile? {
        guard let bestFileId = bestFileId else { return files.first }
        return files.first { $0.id == bestFileId }
    }
    
    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.fileSize }
    }
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var potentialSpaceSaved: Int64 {
        guard files.count > 1 else { return 0 }
        // Space saved by keeping only the best photo
        return files.reduce(0) { $0 + $1.fileSize } - (bestFile?.fileSize ?? 0)
    }
}