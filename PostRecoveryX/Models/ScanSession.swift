import Foundation
import SwiftData

@Model
final class ScanSession {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var scanPath: String
    var totalFilesFound: Int
    var totalFilesProcessed: Int
    var duplicatesFound: Int
    var totalSpaceSaved: Int64
    var status: SessionStatus
    var error: String?
    
    init(scanPath: String) {
        self.id = UUID()
        self.startDate = Date()
        self.scanPath = scanPath
        self.totalFilesFound = 0
        self.totalFilesProcessed = 0
        self.duplicatesFound = 0
        self.totalSpaceSaved = 0
        self.status = .scanning
    }
}

enum SessionStatus: String, Codable, CaseIterable {
    case scanning = "Scanning"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

extension ScanSession {
    var duration: TimeInterval? {
        guard let endDate = endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }
    
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }
    
    var progress: Double {
        guard totalFilesFound > 0 else { return 0 }
        return Double(totalFilesProcessed) / Double(totalFilesFound)
    }
    
    var formattedSpaceSaved: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSpaceSaved)
    }
}