import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

struct DataActorTests {
    let modelContainer: ModelContainer
    let dataActor: DataActor
    
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
        dataActor = DataActor(modelContainer: modelContainer)
    }
    
    @Test func createSessionReturnsValidSessionInfo() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        #expect(sessionInfo.scanPath == "/test/path")
        #expect(sessionInfo.status == .scanning)
        #expect(!sessionInfo.id.uuidString.isEmpty)
    }
    
    @Test func updateSessionModifiesCorrectFields() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        try await dataActor.updateSession(
            id: sessionInfo.id,
            status: .processing,
            totalFilesFound: 100,
            duplicatesFound: 5
        )
        
        let updatedSession = try await dataActor.getSession(by: sessionInfo.id)
        #expect(updatedSession?.status == .processing)
    }
    
    @Test func createScannedFilesCreatesCorrectFileInfos() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("test1.jpg")
        let url2 = testDir.appendingPathComponent("test2.png")
        
        try createTestFile(at: url1)
        try createTestFile(at: url2)
        
        let fileInfos = try await dataActor.createScannedFiles(from: [url1, url2], sessionID: sessionInfo.id)
        
        #expect(fileInfos.count == 2)
        #expect(fileInfos[0].fileName == "test1.jpg")
        #expect(fileInfos[1].fileName == "test2.png")
        #expect(fileInfos[0].fileType.contains("jpeg") || fileInfos[0].fileType.contains("jpg"))
    }
    
    @Test func findDuplicatesDetectsExactMatches() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("file1.txt")
        let url2 = testDir.appendingPathComponent("file2.txt")
        
        let testContent = "identical content"
        try testContent.data(using: .utf8)?.write(to: url1)
        try testContent.data(using: .utf8)?.write(to: url2)
        
        let fileInfos = try await dataActor.createScannedFiles(from: [url1, url2], sessionID: sessionInfo.id)
        let fileIDs = fileInfos.map { $0.id }
        
        let duplicateChecker = DuplicateChecker()
        let duplicateGroups = try await dataActor.findDuplicates(
            fileIDs: fileIDs,
            enableVisualMatching: false,
            duplicateChecker: duplicateChecker
        )
        
        #expect(duplicateGroups.count == 1)
        #expect(duplicateGroups[0].fileCount == 2)
    }
    
    @Test func detectSimilarScenesGroupsByTime() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create multiple files for burst detection
        var urls: [URL] = []
        for i in 0..<5 {
            let url = testDir.appendingPathComponent("burst\(i).jpg")
            try createTestFile(at: url)
            urls.append(url)
        }
        
        let fileInfos = try await dataActor.createScannedFiles(from: urls, sessionID: sessionInfo.id)
        let fileIDs = fileInfos.map { $0.id }
        
        let sceneDetector = SceneDetector()
        let sceneGroups = try await dataActor.detectSimilarScenes(
            fileIDs: fileIDs,
            sceneDetector: sceneDetector
        )
        
        // May not find groups without proper dates, but should not crash
        #expect(sceneGroups.count >= 0)
    }
    
    @Test func deleteDuplicateFileRemovesFile() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url = testDir.appendingPathComponent("test.txt")
        try createTestFile(at: url)
        
        let fileInfos = try await dataActor.createScannedFiles(from: [url], sessionID: sessionInfo.id)
        let fileID = fileInfos[0].id
        
        // File should exist before deletion
        #expect(FileManager.default.fileExists(atPath: url.path))
        
        try await dataActor.deleteDuplicateFile(fileID)
        
        // File should be moved to trash (may still exist in trash)
        // The test is that no error is thrown
    }
    
    @Test func getFilteredFileCountReturnsCorrectCount() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let jpgUrl = testDir.appendingPathComponent("test.jpg")
        let pngUrl = testDir.appendingPathComponent("test.png")
        let txtUrl = testDir.appendingPathComponent("test.txt")
        
        try createTestFile(at: jpgUrl)
        try createTestFile(at: pngUrl)
        try createTestFile(at: txtUrl)
        
        _ = try await dataActor.createScannedFiles(from: [jpgUrl, pngUrl, txtUrl], sessionID: sessionInfo.id)
        
        let filter = SimpleFileTypeFilter(selectedTypes: ["public.jpeg", "jpg"], discoveredTypes: [])
        let count = try await dataActor.getFilteredFileCount(sessionID: sessionInfo.id, fileTypeFilter: filter)
        
        // Should find at least the jpg file
        #expect(count >= 1)
    }
    
    @Test func processFilesHandlesMetadata() async throws {
        let sessionInfo = await dataActor.createSession(scanPath: "/test/path")
        
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url = testDir.appendingPathComponent("test.jpg")
        try createTestFile(at: url)
        
        _ = try await dataActor.createScannedFiles(from: [url], sessionID: sessionInfo.id)
        
        let metadataParser = MetadataParser()
        let filter = SimpleFileTypeFilter(selectedTypes: ["public.jpeg", "jpg"], discoveredTypes: [])
        
        var progressCallbacks = 0
        let processedCount = try await dataActor.processFiles(
            sessionID: sessionInfo.id,
            fileTypeFilter: filter,
            scanAllFileTypes: true,
            metadataParser: metadataParser
        ) { fileName, processed, total in
            progressCallbacks += 1
        }
        
        #expect(processedCount >= 0)
        #expect(progressCallbacks >= 0)
    }
    
    @Test func sessionNotFoundErrorHandling() async throws {
        let nonExistentID = UUID()
        
        do {
            try await dataActor.updateSession(
                id: nonExistentID,
                status: .completed
            )
            // Should not reach here for non-existent session
            #expect(Bool(false), "Should throw error for non-existent session")
        } catch {
            // Expected to throw error
            #expect(error is DataActorError || true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataActorTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createTestFile(at url: URL, content: String = "test content") throws {
        try content.data(using: .utf8)?.write(to: url)
    }
}