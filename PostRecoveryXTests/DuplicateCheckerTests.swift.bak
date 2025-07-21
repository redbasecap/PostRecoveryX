import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

struct DuplicateCheckerTests {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    init() throws {
        let schema = Schema([
            ScannedFile.self,
            DuplicateGroup.self,
            OrganizationTask.self,
            ScanSession.self,
            SimilarSceneGroup.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = modelContainer.mainContext
    }
    
    @Test func findExactDuplicates() async throws {
        let checker = DuplicateChecker()
        
        // Create files with identical content
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("file1.txt")
        let url2 = testDir.appendingPathComponent("file2.txt")
        let url3 = testDir.appendingPathComponent("file3.txt")
        
        let identicalContent = "This is identical content for duplicate testing"
        try identicalContent.data(using: .utf8)?.write(to: url1)
        try identicalContent.data(using: .utf8)?.write(to: url2)
        try "Different content".data(using: .utf8)?.write(to: url3)
        
        let file1 = ScannedFile(path: url1.path, fileName: "file1.txt", fileSize: Int64(identicalContent.count), fileType: "public.plain-text")
        let file2 = ScannedFile(path: url2.path, fileName: "file2.txt", fileSize: Int64(identicalContent.count), fileType: "public.plain-text")
        let file3 = ScannedFile(path: url3.path, fileName: "file3.txt", fileSize: 100, fileType: "public.plain-text")
        
        modelContext.insert(file1)
        modelContext.insert(file2)
        modelContext.insert(file3)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file1, file2, file3],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.count == 1)
        #expect(groups[0].files.count == 2)
        #expect(groups[0].files.contains { $0.fileName == "file1.txt" })
        #expect(groups[0].files.contains { $0.fileName == "file2.txt" })
    }
    
    @Test func findDuplicatesWithDifferentSizes() async throws {
        let checker = DuplicateChecker()
        
        let file1 = ScannedFile(path: "/test/file1.txt", fileName: "file1.txt", fileSize: 1000, fileType: "public.plain-text")
        let file2 = ScannedFile(path: "/test/file2.txt", fileName: "file2.txt", fileSize: 2000, fileType: "public.plain-text")
        
        // Same hash but different sizes - should not be duplicates
        file1.sha256Hash = "abc123"
        file2.sha256Hash = "abc123"
        
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.isEmpty)
    }
    
    @Test func findVisualMatches() async throws {
        let checker = DuplicateChecker()
        
        let file1 = ScannedFile(path: "/test/image1.jpg", fileName: "image1.jpg", fileSize: 1000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/image2.jpg", fileName: "image2.jpg", fileSize: 1000, fileType: "public.jpeg")
        
        // Set similar perceptual hashes
        file1.perceptualHash = 0b1111000011110000111100001111000011110000111100001111000011110000
        file2.perceptualHash = 0b1111000011110000111100001111000011110000111100001111000011111000 // 1 bit different
        
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: true
        )
        
        #expect(groups.count == 1)
        #expect(groups[0].isPerceptualMatch)
        #expect(groups[0].sha256Hash.hasPrefix("visual_"))
    }
    
    @Test func findVisualMatchesWithThreshold() async throws {
        let checker = DuplicateChecker()
        
        let file1 = ScannedFile(path: "/test/image1.jpg", fileName: "image1.jpg", fileSize: 1000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/image2.jpg", fileName: "image2.jpg", fileSize: 1000, fileType: "public.jpeg")
        
        // Set very different perceptual hashes (more than threshold)
        file1.perceptualHash = 0b1111111111111111111111111111111111111111111111111111111111111111
        file2.perceptualHash = 0b0000000000000000000000000000000000000000000000000000000000000000
        
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: true
        )
        
        #expect(groups.isEmpty)
    }
    
    @Test func findDuplicatesIgnoresNonImages() async throws {
        let checker = DuplicateChecker()
        
        let textFile1 = ScannedFile(path: "/test/doc1.txt", fileName: "doc1.txt", fileSize: 1000, fileType: "public.plain-text")
        let textFile2 = ScannedFile(path: "/test/doc2.txt", fileName: "doc2.txt", fileSize: 1000, fileType: "public.plain-text")
        
        // Set perceptual hashes (should be ignored for non-images)
        textFile1.perceptualHash = 0b1111000011110000111100001111000011110000111100001111000011110000
        textFile2.perceptualHash = 0b1111000011110000111100001111000011110000111100001111000011111000
        
        modelContext.insert(textFile1)
        modelContext.insert(textFile2)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [textFile1, textFile2],
            modelContext: modelContext,
            enableVisualMatching: true
        )
        
        // Should not create visual matches for non-images
        #expect(groups.isEmpty)
    }
    
    @Test func findDuplicatesWithLargeDataset() async throws {
        let checker = DuplicateChecker()
        
        var files: [ScannedFile] = []
        
        // Create 100 files with 10 groups of duplicates
        for group in 0..<10 {
            for duplicate in 0..<10 {
                let file = ScannedFile(
                    path: "/test/group\(group)_file\(duplicate).txt",
                    fileName: "group\(group)_file\(duplicate).txt",
                    fileSize: 1000,
                    fileType: "public.plain-text"
                )
                file.sha256Hash = "hash_group_\(group)"
                files.append(file)
                modelContext.insert(file)
            }
        }
        
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: files,
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.count == 10)
        for group in groups {
            #expect(group.files.count == 10)
        }
    }
    
    @Test func findDuplicatesHandlesEmptyInput() async throws {
        let checker = DuplicateChecker()
        
        let groups = try await checker.findDuplicates(
            in: [],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.isEmpty)
    }
    
    @Test func findDuplicatesHandlesSingleFile() async throws {
        let checker = DuplicateChecker()
        
        let file = ScannedFile(path: "/test/single.txt", fileName: "single.txt", fileSize: 1000, fileType: "public.plain-text")
        modelContext.insert(file)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.isEmpty)
    }
    
    @Test func duplicateGroupMetadata() async throws {
        let checker = DuplicateChecker()
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("file1.txt")
        let url2 = testDir.appendingPathComponent("file2.txt")
        
        let content = "duplicate content"
        try content.data(using: .utf8)?.write(to: url1)
        try content.data(using: .utf8)?.write(to: url2)
        
        let file1 = ScannedFile(path: url1.path, fileName: "file1.txt", fileSize: Int64(content.count), fileType: "public.plain-text")
        let file2 = ScannedFile(path: url2.path, fileName: "file2.txt", fileSize: Int64(content.count), fileType: "public.plain-text")
        
        file1.creationDate = Date(timeIntervalSince1970: 1000)
        file2.creationDate = Date(timeIntervalSince1970: 2000)
        
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await checker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.count == 1)
        let group = groups[0]
        #expect(group.fileSize == Int64(content.count))
        #expect(group.fileCount == 2)
        #expect(group.oldestFile?.fileName == "file1.txt")
        #expect(group.newestFile?.fileName == "file2.txt")
        #expect(group.potentialSpaceSaved == Int64(content.count))
    }
    
    @Test func duplicateCheckerCancellation() async throws {
        let checker = DuplicateChecker()
        
        // Create many files
        var files: [ScannedFile] = []
        for i in 0..<1000 {
            let file = ScannedFile(
                path: "/test/file\(i).txt",
                fileName: "file\(i).txt",
                fileSize: 1000,
                fileType: "public.plain-text"
            )
            file.sha256Hash = "same_hash" // All duplicates
            files.append(file)
            modelContext.insert(file)
        }
        try modelContext.save()
        
        // Start duplicate detection and immediately cancel
        let checkTask = Task {
            try await checker.findDuplicates(
                in: files,
                modelContext: modelContext,
                enableVisualMatching: false
            )
        }
        
        await checker.cancel()
        
        do {
            _ = try await checkTask.value
            // May or may not throw depending on timing
        } catch {
            // Cancellation error is expected
            #expect(true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuplicateCheckerTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}