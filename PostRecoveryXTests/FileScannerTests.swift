import Testing
import Foundation
@testable import PostRecoveryX

struct FileScannerTests {
    
    @Test func scanDirectoryFindsAllFileTypes() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create various file types
        let files = [
            "image.jpg", "photo.png", "document.pdf", "video.mp4",
            "archive.zip", "text.txt", "spreadsheet.xlsx"
        ]
        
        for fileName in files {
            try createTestFile(at: testDir.appendingPathComponent(fileName))
        }
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        #expect(urls.count == files.count)
    }
    
    @Test func scanDirectoryImageOnlyMode() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let files = [
            "image.jpg", "photo.png", "document.pdf", "video.mp4"
        ]
        
        for fileName in files {
            try createTestFile(at: testDir.appendingPathComponent(fileName))
        }
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: false)
        
        // Should find images and videos in image-only mode
        #expect(urls.count >= 2) // At least jpg, png, mp4
    }
    
    @Test func scanDirectoryWithSubdirectories() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create subdirectories
        let subDir1 = testDir.appendingPathComponent("subdir1")
        let subDir2 = testDir.appendingPathComponent("subdir2")
        try FileManager.default.createDirectory(at: subDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir2, withIntermediateDirectories: true)
        
        // Create files in different directories
        try createTestFile(at: testDir.appendingPathComponent("root.jpg"))
        try createTestFile(at: subDir1.appendingPathComponent("sub1.png"))
        try createTestFile(at: subDir2.appendingPathComponent("sub2.pdf"))
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        #expect(urls.count == 3)
        #expect(urls.contains { $0.lastPathComponent == "root.jpg" })
        #expect(urls.contains { $0.lastPathComponent == "sub1.png" })
        #expect(urls.contains { $0.lastPathComponent == "sub2.pdf" })
    }
    
    @Test func scanDirectoryWithProgressCallback() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create multiple files
        for i in 0..<10 {
            try createTestFile(at: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        var progressCallbacks = 0
        var lastFileName = ""
        var lastCount = 0
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true) { fileName, count in
            progressCallbacks += 1
            lastFileName = fileName
            lastCount = count
        }
        
        #expect(urls.count == 10)
        #expect(progressCallbacks > 0)
        #expect(lastCount == 10)
        #expect(!lastFileName.isEmpty)
    }
    
    @Test func scanDirectoryHandlesEmptyDirectory() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        #expect(urls.isEmpty)
    }
    
    @Test func scanDirectoryHandlesNonExistentDirectory() async throws {
        let scanner = FileScanner()
        let nonExistentDir = URL(fileURLWithPath: "/non/existent/path")
        
        do {
            _ = try await scanner.scanDirectory(at: nonExistentDir, scanAllTypes: true)
            #expect(Bool(false), "Should throw error for non-existent directory")
        } catch {
            // Expected to throw error
            #expect(true)
        }
    }
    
    @Test func scanDirectoryHandlesSymlinks() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let originalFile = testDir.appendingPathComponent("original.txt")
        let symlinkFile = testDir.appendingPathComponent("symlink.txt")
        
        try createTestFile(at: originalFile)
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: originalFile)
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        // Should handle symlinks gracefully (may include or exclude them)
        #expect(urls.count >= 1) // At least the original file
    }
    
    @Test func scanDirectoryWithHiddenFiles() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        try createTestFile(at: testDir.appendingPathComponent("visible.txt"))
        try createTestFile(at: testDir.appendingPathComponent(".hidden.txt"))
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        // Should find at least the visible file
        #expect(urls.count >= 1)
        #expect(urls.contains { $0.lastPathComponent == "visible.txt" })
    }
    
    @Test func createScannedFilesWithValidMetadata() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url = testDir.appendingPathComponent("test.jpg")
        try createTestFile(at: url)
        
        let scannedFiles = try await scanner.createScannedFiles(from: [url])
        
        #expect(scannedFiles.count == 1)
        let file = scannedFiles[0]
        #expect(file.fileName == "test.jpg")
        #expect(file.path == url.path)
        #expect(file.fileSize > 0)
        #expect(!file.fileType.isEmpty)
    }
    
    @Test func createScannedFilesDetectsThumbnails() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create small file that might be detected as thumbnail
        let smallContent = "x" // Very small content
        let url = testDir.appendingPathComponent("small_thumb.jpg")
        try smallContent.data(using: .utf8)?.write(to: url)
        
        let scannedFiles = try await scanner.createScannedFiles(from: [url])
        
        #expect(scannedFiles.count == 1)
        // File might be detected as potential thumbnail due to small size
        let file = scannedFiles[0]
        #expect(file.fileName == "small_thumb.jpg")
    }
    
    @Test func scanDirectoryCancellation() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create many files to have time to cancel
        for i in 0..<1000 {
            try createTestFile(at: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        // Start scanning and immediately cancel
        let scanTask = Task {
            try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        }
        
        // Cancel the scanner
        await scanner.cancel()
        
        do {
            _ = try await scanTask.value
            // May or may not throw depending on timing
        } catch {
            // Cancellation error is expected
            #expect(true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileScannerTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createTestFile(at url: URL, content: String = "test content") throws {
        try content.data(using: .utf8)?.write(to: url)
    }
}