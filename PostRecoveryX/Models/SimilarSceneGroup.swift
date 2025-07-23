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
    @Relationship(inverse: \ScanSession.similarSceneGroups)
    var scanSession: ScanSession?
    
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
    case unknown = "Unknown"
}