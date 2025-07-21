import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

struct ModelValidationTests {
    
    @Test func scannedFileModelProperties() async throws {
        let file = ScannedFile(
            path: "/test/documents/image.jpg",
            fileName: "image.jpg",
            fileSize: 2048000, // 2MB
            fileType: "public.jpeg"
        )
        
        file.width = 1920
        file.height = 1080
        file.sha256Hash = "abc123def456"
        file.creationDate = Date(timeIntervalSince1970: 1640995200) // 2022-01-01
        file.originalCreationDate = Date(timeIntervalSince1970: 1640995200)
        file.cameraMake = "Apple"
        file.cameraModel = "iPhone 13"
        file.perceptualHash = 0x123456789ABCDEF0
        
        #expect(file.fileName == "image.jpg")
        #expect(file.fileSize == 2048000)
        #expect(file.formattedFileSize == "2 MB")
        #expect(file.isImage)
        #expect(!file.isVideo)
        #expect(file.hasMetadata)
        #expect(file.url.path == "/test/documents/image.jpg")
        #expect(file.fileExtension == "jpg")
        #expect(file.metadataQualityScore > 0)
        #expect(!file.isPotentialThumbnail) // 2MB is not thumbnail size
    }
    
    @Test func scannedFileVideoProperties() async throws {
        let file = ScannedFile(
            path: "/test/videos/movie.mp4",
            fileName: "movie.mp4",
            fileSize: 50000000, // 50MB
            fileType: "public.mpeg-4"
        )
        
        #expect(file.fileName == "movie.mp4")
        #expect(file.isVideo)
        #expect(!file.isImage)
        #expect(file.fileExtension == "mp4")
    }
    
    @Test func scannedFileThumbnailDetection() async throws {
        let smallFile = ScannedFile(
            path: "/test/thumbs/small.jpg",
            fileName: "small.jpg",
            fileSize: 5000, // 5KB
            fileType: "public.jpeg"
        )
        smallFile.width = 150
        smallFile.height = 150
        
        #expect(smallFile.isPotentialThumbnail)
        
        let largeFile = ScannedFile(
            path: "/test/images/large.jpg",
            fileName: "large.jpg",
            fileSize: 5000000, // 5MB
            fileType: "public.jpeg"
        )
        largeFile.width = 4000
        largeFile.height = 3000
        
        #expect(!largeFile.isPotentialThumbnail)
    }
    
    @Test func scannedFileOrganizationPath() async throws {
        let file = ScannedFile(
            path: "/source/IMG_1234.jpg",
            fileName: "IMG_1234.jpg",
            fileSize: 1000000,
            fileType: "public.jpeg"
        )
        file.originalCreationDate = DateComponents(calendar: .current, year: 2023, month: 8, day: 15).date
        
        #expect(file.suggestedOrganizationPath?.contains("2023") == true)
        #expect(file.suggestedOrganizationPath?.contains("08") == true)
    }
    
    @Test func duplicateGroupModel() async throws {
        let group = DuplicateGroup(sha256Hash: "test123", fileSize: 1024000)
        
        let file1 = ScannedFile(path: "/test/file1.jpg", fileName: "file1.jpg", fileSize: 1024000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/file2.jpg", fileName: "file2.jpg", fileSize: 1024000, fileType: "public.jpeg")
        let file3 = ScannedFile(path: "/test/file3.jpg", fileName: "file3.jpg", fileSize: 1024000, fileType: "public.jpeg")
        
        file1.creationDate = Date(timeIntervalSince1970: 1000)
        file1.fileSize = 512000
        file1.width = 1920
        file1.height = 1080
        file1.hasMetadata = true
        
        file2.creationDate = Date(timeIntervalSince1970: 2000)
        file2.fileSize = 1024000
        file2.width = 1280
        file2.height = 720
        
        file3.creationDate = Date(timeIntervalSince1970: 1500)
        file3.fileSize = 2048000
        file3.isThumbnail = true
        
        group.files = [file1, file2, file3]
        group.fileCount = 3
        
        #expect(group.oldestFile?.fileName == "file1.jpg")
        #expect(group.newestFile?.fileName == "file2.jpg")
        #expect(group.largestFile?.fileName == "file3.jpg")
        #expect(group.bestQualityFile?.fileName == "file1.jpg") // Highest metadata score
        #expect(group.hasLowQualityFiles) // file3 is thumbnail
        #expect(group.potentialSpaceSaved == 2048000) // fileSize * (count - 1)
        #expect(!group.formattedSpaceSaved.isEmpty)
    }
    
    @Test func duplicateGroupPerceptualMatch() async throws {
        let group = DuplicateGroup(sha256Hash: "visual_abc123", fileSize: 1024)
        
        #expect(group.isPerceptualMatch)
        
        let exactGroup = DuplicateGroup(sha256Hash: "exact_abc123", fileSize: 1024)
        #expect(!exactGroup.isPerceptualMatch)
    }
    
    @Test func scanSessionModel() async throws {
        let session = ScanSession(scanPath: "/test/scan/path")
        
        #expect(session.scanPath == "/test/scan/path")
        #expect(session.status == .scanning)
        #expect(session.totalFilesFound == 0)
        #expect(session.totalFilesProcessed == 0)
        #expect(session.duplicatesFound == 0)
        #expect(session.totalSpaceSaved == 0)
        #expect(session.error == nil)
        #expect(session.endDate == nil)
        #expect(!session.id.uuidString.isEmpty)
    }
    
    @Test func scanSessionStatusTransitions() async throws {
        let session = ScanSession(scanPath: "/test")
        
        session.status = .processing
        #expect(session.status == .processing)
        
        session.status = .completed
        #expect(session.status == .completed)
        
        session.status = .failed
        #expect(session.status == .failed)
        
        session.status = .cancelled
        #expect(session.status == .cancelled)
    }
    
    @Test func organizationTaskModel() async throws {
        let task = OrganizationTask(
            sourcePath: "/source/image.jpg",
            destinationPath: "/dest/2023/08/image.jpg",
            fileName: "image.jpg",
            action: .copy
        )
        
        #expect(task.sourcePath == "/source/image.jpg")
        #expect(task.destinationPath == "/dest/2023/08/image.jpg")
        #expect(task.fileName == "image.jpg")
        #expect(task.action == .copy)
        #expect(task.status == .pending)
        #expect(task.error == nil)
        #expect(!task.id.uuidString.isEmpty)
    }
    
    @Test func organizationTaskExecution() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let sourceFile = testDir.appendingPathComponent("source.txt")
        let destDir = testDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        try "test content".data(using: .utf8)?.write(to: sourceFile)
        
        let task = OrganizationTask(
            sourcePath: sourceFile.path,
            destinationPath: destDir.path,
            fileName: "source.txt",
            action: .copy
        )
        
        try await task.execute()
        
        #expect(task.status == .completed)
        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("source.txt").path))
    }
    
    @Test func similarSceneGroupModel() async throws {
        let group = SimilarSceneGroup()
        
        let file1 = ScannedFile(path: "/test/burst1.jpg", fileName: "burst1.jpg", fileSize: 1000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/burst2.jpg", fileName: "burst2.jpg", fileSize: 1000, fileType: "public.jpeg")
        
        file1.creationDate = Date(timeIntervalSince1970: 1000)
        file2.creationDate = Date(timeIntervalSince1970: 1002) // 2 seconds later
        
        group.files = [file1, file2]
        group.fileCount = 2
        group.groupType = .burst
        group.timeRange = 2.0
        group.locationInfo = "Vacation Photos"
        group.averagePerceptualHash = 0x123456789ABCDEF0
        group.bestFileId = file1.id
        
        #expect(group.fileCount == 2)
        #expect(group.groupType == .burst)
        #expect(group.timeRange == 2.0)
        #expect(group.locationInfo == "Vacation Photos")
        #expect(group.bestFileId == file1.id)
        #expect(!group.id.uuidString.isEmpty)
    }
    
    @Test func sceneGroupTypeEnum() async throws {
        #expect(SceneGroupType.burst.rawValue == "burst")
        #expect(SceneGroupType.sequence.rawValue == "sequence")
        #expect(SceneGroupType.event.rawValue == "event")
    }
    
    @Test func resolutionActionEnum() async throws {
        let actions = ResolutionAction.allCases
        
        #expect(actions.contains(.keepOldest))
        #expect(actions.contains(.keepNewest))
        #expect(actions.contains(.keepLargest))
        #expect(actions.contains(.keepBestQuality))
        #expect(actions.contains(.keepSelected))
        #expect(actions.contains(.keepAll))
        #expect(actions.contains(.deleteAll))
    }
    
    @Test func sessionStatusEnum() async throws {
        #expect(SessionStatus.scanning.rawValue == "scanning")
        #expect(SessionStatus.processing.rawValue == "processing")
        #expect(SessionStatus.completed.rawValue == "completed")
        #expect(SessionStatus.failed.rawValue == "failed")
        #expect(SessionStatus.cancelled.rawValue == "cancelled")
    }
    
    @Test func organizationActionEnum() async throws {
        #expect(OrganizationAction.copy.rawValue == "copy")
        #expect(OrganizationAction.move.rawValue == "move")
    }
    
    @Test func fileNamingModeEnum() async throws {
        let modes = FileNamingMode.allCases
        
        #expect(modes.contains(.keepOriginal))
        #expect(modes.contains(.datePrefix))
        #expect(modes.contains(.fullRename))
    }
    
    @Test func fileTypeConfigurationModel() async throws {
        let imageCategory = FileTypeCategory.images
        
        #expect(imageCategory.name == "Images")
        #expect(imageCategory.systemImage == "photo")
        #expect(!imageCategory.types.isEmpty)
        #expect(!imageCategory.extensions.isEmpty)
    }
    
    @Test func simpleFileTypeFilterModel() async throws {
        let filter = SimpleFileTypeFilter(
            selectedTypes: ["public.jpeg", "public.png"],
            discoveredTypes: ["public.jpeg", "public.png", "public.pdf"]
        )
        
        #expect(filter.hasSelection)
        #expect(filter.shouldInclude(fileType: "public.jpeg"))
        #expect(!filter.shouldInclude(fileType: "public.pdf"))
        #expect(filter.isSelected("public.jpeg"))
        
        let toggledFilter = filter.toggle("public.pdf")
        #expect(toggledFilter.isSelected("public.pdf"))
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelValidationTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}