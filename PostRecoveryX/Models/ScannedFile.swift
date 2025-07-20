import Foundation
import SwiftData

@Model
final class ScannedFile {
    var id: UUID
    var path: String
    var fileName: String
    var fileSize: Int64
    var fileType: String
    var sha256Hash: String?
    var perceptualHash: UInt64?
    var creationDate: Date?
    var modificationDate: Date?
    var originalCreationDate: Date?
    var width: Int?
    var height: Int?
    var cameraModel: String?
    var duplicateGroup: DuplicateGroup?
    var similarSceneGroup: SimilarSceneGroup?
    var isProcessed: Bool
    var hasMetadata: Bool
    var error: String?
    var isThumbnail: Bool
    var suggestedRotation: Int? // Rotation in degrees (90, 180, 270, -90, -180, -270)
    
    init(path: String, fileName: String, fileSize: Int64, fileType: String) {
        self.id = UUID()
        self.path = path
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileType = fileType
        self.isProcessed = false
        self.hasMetadata = false
        self.isThumbnail = false
    }
}

extension ScannedFile {
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var isPotentialThumbnail: Bool {
        // Check file size (under 10KB is likely a thumbnail)
        let sizeThreshold: Int64 = 10 * 1024 // 10KB
        
        // Check filename patterns
        let thumbnailPatterns = ["thumb", "thumbnail", "tn_", "_tn", "small", "_s", "-s"]
        let lowercaseFileName = fileName.lowercased()
        let hasThumbPattern = thumbnailPatterns.contains { pattern in
            lowercaseFileName.contains(pattern)
        }
        
        // Check dimensions if available
        var hasSmallDimensions = false
        if let width = width, let height = height {
            hasSmallDimensions = width <= 200 || height <= 200
        }
        
        return fileSize <= sizeThreshold || hasThumbPattern || hasSmallDimensions
    }
    
    var suggestedOrganizationPath: String? {
        guard let date = originalCreationDate ?? creationDate else { return nil }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let monthName = DateFormatter().monthSymbols[month - 1]
        let topFolder = url.deletingLastPathComponent().lastPathComponent
        return "\(year)/\(String(format: "%02d", month)) - \(monthName)/\(topFolder)"
    }
    
    var metadataQualityScore: Int {
        var score = 0
        
        // Base score for having the file
        score += 10
        
        // Original creation date is most valuable (30 points)
        if originalCreationDate != nil {
            score += 30
        } else if creationDate != nil {
            score += 10
        }
        
        // Camera model indicates original photo (20 points)
        if cameraModel != nil {
            score += 20
        }
        
        // Dimensions indicate full resolution (15 points)
        if let w = width, let h = height {
            if w >= 3000 || h >= 3000 {
                score += 15  // High resolution
            } else if w >= 1920 || h >= 1920 {
                score += 10  // Medium resolution
            } else if w >= 1024 || h >= 1024 {
                score += 5   // Low resolution
            }
        }
        
        // Having metadata at all (10 points)
        if hasMetadata {
            score += 10
        }
        
        // File size bonus (larger usually = better quality)
        if fileSize > 5_000_000 { // > 5MB
            score += 10
        } else if fileSize > 1_000_000 { // > 1MB
            score += 5
        }
        
        // Penalty for being identified as thumbnail
        if isThumbnail || isPotentialThumbnail {
            score -= 20
        }
        
        // Penalty for having errors
        if error != nil {
            score -= 10
        }
        
        return max(0, score) // Don't go below 0
    }
}