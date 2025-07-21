import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

struct PerformanceTests {
    let modelContainer: ModelContainer
    
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
    }
    
    @Test func fileScannerPerformanceSmallDataset() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create 100 files
        for i in 0..<100 {
            try createTestFile(at: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        let startTime = Date()
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(urls.count == 100)
        #expect(duration < 5.0) // Should complete within 5 seconds
        
        print("Scanned 100 files in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func fileScannerPerformanceMediumDataset() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create 1000 files
        for i in 0..<1000 {
            try createTestFile(at: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        let startTime = Date()
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(urls.count == 1000)
        #expect(duration < 30.0) // Should complete within 30 seconds
        
        print("Scanned 1000 files in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func duplicateDetectionPerformance() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let duplicateChecker = DuplicateChecker()
        
        // Create session
        let sessionInfo = await dataActor.createSession(scanPath: "/test")
        
        // Create many files with some duplicates
        var fileIDs: [UUID] = []
        let modelContext = modelContainer.mainContext
        
        for group in 0..<50 { // 50 groups
            for duplicate in 0..<10 { // 10 duplicates each = 500 files
                let file = ScannedFile(
                    path: "/test/group\(group)_file\(duplicate).txt",
                    fileName: "group\(group)_file\(duplicate).txt",
                    fileSize: 1000,
                    fileType: "public.plain-text"
                )
                file.sha256Hash = "hash_group_\(group)"
                
                modelContext.insert(file)
                fileIDs.append(file.id)
            }
        }
        try modelContext.save()
        
        let startTime = Date()
        let duplicateGroups = try await dataActor.findDuplicates(
            fileIDs: fileIDs,
            enableVisualMatching: false,
            duplicateChecker: duplicateChecker
        )
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(duplicateGroups.count == 50)
        #expect(duration < 10.0) // Should complete within 10 seconds
        
        print("Detected duplicates in 500 files in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func dataActorPerformance() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        var urls: [URL] = []
        for i in 0..<200 {
            let url = testDir.appendingPathComponent("file\(i).txt")
            try createTestFile(at: url)
            urls.append(url)
        }
        
        let sessionInfo = await dataActor.createSession(scanPath: testDir.path)
        
        let startTime = Date()
        let fileInfos = try await dataActor.createScannedFiles(from: urls, sessionID: sessionInfo.id)
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(fileInfos.count == 200)
        #expect(duration < 5.0) // Should complete within 5 seconds
        
        print("Created 200 scanned file records in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func memoryUsageUnderLoad() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create many small files
        for i in 0..<5000 {
            let content = "File content \(i)"
            try content.data(using: .utf8)?.write(to: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        // Monitor memory during scan
        let startMemory = getMemoryUsage()
        
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true) { fileName, count in
            // Progress callback to simulate real usage
        }
        
        let endMemory = getMemoryUsage()
        let memoryIncrease = endMemory - startMemory
        
        #expect(urls.count == 5000)
        #expect(memoryIncrease < 100_000_000) // Less than 100MB increase
        
        print("Memory increase during scan: \(String(format: "%.1f", Double(memoryIncrease) / 1_000_000)) MB")
    }
    
    @Test func concurrentOperationsPerformance() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create subdirectories with files
        for subdir in 0..<5 {
            let subdirURL = testDir.appendingPathComponent("subdir\(subdir)")
            try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
            
            for file in 0..<20 {
                try createTestFile(at: subdirURL.appendingPathComponent("file\(file).txt"))
            }
        }
        
        let startTime = Date()
        
        // Perform concurrent scans of subdirectories
        try await withThrowingTaskGroup(of: [URL].self) { group in
            for subdir in 0..<5 {
                let subdirURL = testDir.appendingPathComponent("subdir\(subdir)")
                group.addTask {
                    try await scanner.scanDirectory(at: subdirURL, scanAllTypes: true)
                }
            }
            
            var totalFiles = 0
            for try await urls in group {
                totalFiles += urls.count
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            #expect(totalFiles == 100) // 5 subdirs * 20 files each
            #expect(duration < 10.0) // Should complete within 10 seconds
            
            print("Concurrent scan of 100 files completed in \(String(format: "%.3f", duration)) seconds")
        }
    }
    
    @Test func largeFileHandlingPerformance() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create a few larger files
        for i in 0..<5 {
            let largeContent = String(repeating: "Large file content ", count: 50000) // ~1MB each
            try largeContent.data(using: .utf8)?.write(to: testDir.appendingPathComponent("large\(i).txt"))
        }
        
        let startTime = Date()
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        let scannedFiles = try await scanner.createScannedFiles(from: urls)
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(scannedFiles.count == 5)
        #expect(duration < 5.0) // Should complete within 5 seconds
        
        // Verify file sizes are correct
        for file in scannedFiles {
            #expect(file.fileSize > 500_000) // Should be > 500KB
        }
        
        print("Processed 5 large files in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func organizationTaskBatchPerformance() async throws {
        let testDir = createTestDirectory()
        let destDir = testDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create source files
        var tasks: [OrganizationTask] = []
        for i in 0..<50 {
            let sourceFile = testDir.appendingPathComponent("source\(i).txt")
            try createTestFile(at: sourceFile)
            
            let task = OrganizationTask(
                sourcePath: sourceFile.path,
                destinationPath: destDir.path,
                fileName: "source\(i).txt",
                action: .copy
            )
            tasks.append(task)
        }
        
        let startTime = Date()
        
        // Execute all tasks
        for task in tasks {
            try await task.execute()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(duration < 5.0) // Should complete within 5 seconds
        
        // Verify all files were copied
        for i in 0..<50 {
            let destFile = destDir.appendingPathComponent("source\(i).txt")
            #expect(FileManager.default.fileExists(atPath: destFile.path))
        }
        
        print("Organized 50 files in \(String(format: "%.3f", duration)) seconds")
    }
    
    @Test func sceneDetectionPerformance() async throws {
        let dataActor = DataActor(modelContainer: modelContainer)
        let modelContext = modelContainer.mainContext
        
        // Create session
        let sessionInfo = await dataActor.createSession(scanPath: "/test")
        
        // Create files with dates for scene detection
        var fileIDs: [UUID] = []
        let baseDate = Date(timeIntervalSince1970: 1640995200) // 2022-01-01
        
        for i in 0..<100 {
            let file = ScannedFile(
                path: "/test/image\(i).jpg",
                fileName: "image\(i).jpg",
                fileSize: 1000000,
                fileType: "public.jpeg"
            )
            
            // Create burst groups (close timestamps)
            if i % 10 < 5 {
                file.originalCreationDate = baseDate.addingTimeInterval(TimeInterval(i / 10) * 60 + TimeInterval(i % 5))
            } else {
                file.originalCreationDate = baseDate.addingTimeInterval(TimeInterval(i) * 3600) // 1 hour apart
            }
            
            modelContext.insert(file)
            fileIDs.append(file.id)
        }
        try modelContext.save()
        
        let startTime = Date()
        let sceneGroups = try await dataActor.detectSimilarScenes(
            fileIDs: fileIDs,
            sceneDetector: SceneDetector()
        )
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(duration < 10.0) // Should complete within 10 seconds
        
        print("Scene detection on 100 files completed in \(String(format: "%.3f", duration)) seconds")
        print("Found \(sceneGroups.count) scene groups")
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createTestFile(at url: URL, content: String = "test content") throws {
        try content.data(using: .utf8)?.write(to: url)
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}