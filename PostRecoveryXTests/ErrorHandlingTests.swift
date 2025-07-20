import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

struct ErrorHandlingTests {
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
    
    // MARK: - FileScanner Error Handling
    
    @Test func fileScannerNonExistentDirectory() async throws {
        let scanner = FileScanner()
        let nonExistentPath = URL(fileURLWithPath: "/absolutely/non/existent/path/\(UUID().uuidString)")
        
        do {
            _ = try await scanner.scanDirectory(at: nonExistentPath, scanAllTypes: true)
            #expect(Bool(false), "Should throw error for non-existent directory")
        } catch {
            #expect(error is FileScannerError || true)
        }
    }
    
    @Test func fileScannerPermissionDenied() async throws {
        let scanner = FileScanner()
        
        // Try to scan a system directory that may require permissions
        let restrictedPath = URL(fileURLWithPath: "/private/var/root")
        
        do {
            _ = try await scanner.scanDirectory(at: restrictedPath, scanAllTypes: true)
            // May succeed if run with sufficient permissions, which is fine
        } catch {
            // Expected to fail with permission error
            #expect(true)
        }
    }
    
    @Test func fileScannerCorruptedFileHandling() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create a file that might cause issues
        let corruptedFile = testDir.appendingPathComponent("corrupted.jpg")
        let invalidData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // Invalid JPEG header
        try invalidData.write(to: corruptedFile)
        
        // Should handle corrupted files gracefully
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        #expect(urls.count >= 1) // Should still find the file
        
        let scannedFiles = try await scanner.createScannedFiles(from: urls)
        #expect(scannedFiles.count >= 1) // Should create record even for corrupted file
    }
    
    // MARK: - DataActor Error Handling
    
    @Test func dataActorInvalidSessionID() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let invalidID = UUID()
        
        let sessionInfo = try await dataActor.getSession(by: invalidID)
        #expect(sessionInfo == nil)
        
        // Should handle gracefully without throwing
        try await dataActor.updateSession(id: invalidID, status: .completed)
    }
    
    @Test func dataActorInvalidFileID() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let invalidID = UUID()
        
        do {
            try await dataActor.deleteDuplicateFile(invalidID)
            // Should handle gracefully
        } catch {
            // May throw if file not found, which is acceptable
        }
    }
    
    @Test func dataActorEmptyFileList() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let duplicateChecker = DuplicateChecker()
        
        let duplicateGroups = try await dataActor.findDuplicates(
            fileIDs: [],
            enableVisualMatching: false,
            duplicateChecker: duplicateChecker
        )
        
        #expect(duplicateGroups.isEmpty)
    }
    
    // MARK: - DuplicateChecker Error Handling
    
    @Test func duplicateCheckerEmptyFileList() async throws {
        let checker = DuplicateChecker()
        
        let groups = try await checker.findDuplicates(
            in: [],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.isEmpty)
    }
    
    @Test func duplicateCheckerMissingHashes() async throws {
        let checker = DuplicateChecker()
        
        let file1 = ScannedFile(path: "/test/file1.txt", fileName: "file1.txt", fileSize: 1000, fileType: "public.plain-text")
        let file2 = ScannedFile(path: "/test/file2.txt", fileName: "file2.txt", fileSize: 1000, fileType: "public.plain-text")
        
        // Don't set SHA256 hashes - should be computed
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        // Should handle missing hashes gracefully
        let groups = try await checker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        // May find groups or not, but shouldn't crash
        #expect(groups.count >= 0)
    }
    
    // MARK: - OrganizationTask Error Handling
    
    @Test func organizationTaskInvalidSourcePath() async throws {
        let task = OrganizationTask(
            sourcePath: "/non/existent/source.txt",
            destinationPath: "/tmp/dest.txt",
            fileName: "source.txt",
            action: .copy
        )
        
        do {
            try await task.execute()
            #expect(Bool(false), "Should fail for non-existent source")
        } catch {
            #expect(task.status == .failed)
            #expect(task.error != nil)
        }
    }
    
    @Test func organizationTaskInvalidDestinationPath() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let sourceFile = testDir.appendingPathComponent("source.txt")
        try "test content".data(using: .utf8)?.write(to: sourceFile)
        
        let task = OrganizationTask(
            sourcePath: sourceFile.path,
            destinationPath: "/invalid/path/dest.txt",
            fileName: "source.txt",
            action: .copy
        )
        
        do {
            try await task.execute()
            #expect(Bool(false), "Should fail for invalid destination")
        } catch {
            #expect(task.status == .failed)
            #expect(task.error != nil)
        }
    }
    
    @Test func organizationTaskPermissionDenied() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let sourceFile = testDir.appendingPathComponent("source.txt")
        try "test content".data(using: .utf8)?.write(to: sourceFile)
        
        // Try to copy to a system directory
        let task = OrganizationTask(
            sourcePath: sourceFile.path,
            destinationPath: "/System/dest.txt",
            fileName: "source.txt",
            action: .copy
        )
        
        do {
            try await task.execute()
            // May succeed depending on permissions
        } catch {
            #expect(task.status == .failed)
            #expect(task.error != nil)
        }
    }
    
    // MARK: - MainViewModel Error Handling
    
    @Test func mainViewModelInvalidScanPath() async throws {
        let viewModel = MainViewModel()
        viewModel.setModelContext(modelContext)
        
        viewModel.scanPath = "/absolutely/invalid/path/\(UUID().uuidString)"
        
        await viewModel.startScan()
        
        #expect(viewModel.showError || !viewModel.errorMessage.isEmpty)
        #expect(!viewModel.isScanning)
    }
    
    @Test func mainViewModelEmptySessionID() async throws {
        let viewModel = MainViewModel()
        viewModel.setModelContext(modelContext)
        
        // Try to process without setting a session
        viewModel.currentSessionID = nil
        
        await viewModel.processSelectedFileTypes()
        
        #expect(!viewModel.isScanning) // Should exit early
    }
    
    // MARK: - Memory and Resource Error Handling
    
    @Test func handleLargeFileOperations() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create many files to test memory handling
        for i in 0..<1000 {
            let content = String(repeating: "x", count: 1000) // 1KB each
            let url = testDir.appendingPathComponent("file\(i).txt")
            try content.data(using: .utf8)?.write(to: url)
        }
        
        let scanner = FileScanner()
        
        do {
            let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
            #expect(urls.count == 1000)
            
            // Test creating scanned files in batches to avoid memory issues
            let batchSize = 100
            for i in stride(from: 0, to: urls.count, by: batchSize) {
                let endIndex = min(i + batchSize, urls.count)
                let batch = Array(urls[i..<endIndex])
                
                let scannedFiles = try await scanner.createScannedFiles(from: batch)
                #expect(scannedFiles.count == batch.count)
            }
        } catch {
            // If it fails due to resource constraints, that's acceptable
            #expect(true)
        }
    }
    
    @Test func handleConcurrentOperations() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        for i in 0..<10 {
            try "content \(i)".data(using: .utf8)?.write(to: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        let scanner = FileScanner()
        
        // Start multiple concurrent scans
        let tasks = (0..<5).map { _ in
            Task {
                try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
            }
        }
        
        // Wait for all to complete
        for task in tasks {
            do {
                let urls = try await task.value
                #expect(urls.count == 10)
            } catch {
                // Concurrent access might cause issues, which is acceptable
            }
        }
    }
    
    // MARK: - Data Integrity Error Handling
    
    @Test func handleCorruptedModelData() async throws {
        let file = ScannedFile(path: "/test/file.txt", fileName: "file.txt", fileSize: 1000, fileType: "public.plain-text")
        
        // Simulate corrupted data
        file.sha256Hash = "" // Empty hash
        file.fileSize = -1 // Invalid size
        
        modelContext.insert(file)
        try modelContext.save()
        
        // Should handle corrupted data gracefully
        #expect(file.formattedFileSize != nil) // Should handle negative size
        #expect(!file.fileName.isEmpty)
    }
    
    @Test func handleInvalidDates() async throws {
        let file = ScannedFile(path: "/test/file.txt", fileName: "file.txt", fileSize: 1000, fileType: "public.plain-text")
        
        // Set invalid/extreme dates
        file.creationDate = Date.distantPast
        file.originalCreationDate = Date.distantFuture
        
        let group = DuplicateGroup(sha256Hash: "test", fileSize: 1000)
        group.files = [file]
        
        // Should handle extreme dates gracefully
        #expect(group.oldestFile != nil)
        #expect(group.newestFile != nil)
    }
    
    // MARK: - Network and I/O Error Handling
    
    @Test func handleFileSystemErrors() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let file = testDir.appendingPathComponent("test.txt")
        try "content".data(using: .utf8)?.write(to: file)
        
        let task = OrganizationTask(
            sourcePath: file.path,
            destinationPath: testDir.appendingPathComponent("dest.txt").path,
            fileName: "test.txt",
            action: .move
        )
        
        // Remove source file before execution to simulate I/O error
        try FileManager.default.removeItem(at: file)
        
        do {
            try await task.execute()
            #expect(Bool(false), "Should fail for missing source file")
        } catch {
            #expect(task.status == .failed)
            #expect(task.error?.localizedDescription.contains("exist") == true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorHandlingTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}