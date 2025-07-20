//
//  PostRecoveryXTests.swift
//  PostRecoveryXTests
//
//  Created by Nicola Spieser on 10.07.2025.
//

import XCTest
import SwiftData
@testable import PostRecoveryX

final class PostRecoveryXTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var dataActor: DataActor!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory container for testing
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
        dataActor = DataActor(modelContainer: modelContainer)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        dataActor = nil
        try await super.tearDown()
    }
    
    // MARK: - File Scanner Tests
    
    func testFileScannerDiscovery() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        try createTestFile(at: testDir.appendingPathComponent("test1.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("test2.png"))
        try createTestFile(at: testDir.appendingPathComponent("test3.txt"))
        
        // Scan directory
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        XCTAssertEqual(urls.count, 3, "Should find all 3 files")
    }
    
    func testFileScannerImageOnlyMode() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        try createTestFile(at: testDir.appendingPathComponent("test1.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("test2.png"))
        try createTestFile(at: testDir.appendingPathComponent("test3.txt"))
        
        // Scan directory - image only mode
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: false)
        
        XCTAssertEqual(urls.count, 2, "Should find only 2 image files")
    }
    
    // MARK: - Duplicate Detection Tests
    
    func testExactDuplicateDetection() async throws {
        let duplicateChecker = DuplicateChecker()
        
        // Create test files with same content
        let file1 = ScannedFile(path: "/test/file1.jpg", fileName: "file1.jpg", fileSize: 1000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/file2.jpg", fileName: "file2.jpg", fileSize: 1000, fileType: "public.jpeg")
        
        // Mock same hash
        file1.sha256Hash = "abc123"
        file2.sha256Hash = "abc123"
        
        // Create a session first
        let session = await dataActor.createSession(scanPath: "/test")
        let files = try await dataActor.createScannedFiles(from: [], sessionID: session.id)
        
        // Manually insert our test files
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await duplicateChecker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        XCTAssertEqual(groups.count, 1, "Should find 1 duplicate group")
        XCTAssertEqual(groups.first?.files.count, 2, "Group should contain 2 files")
    }
    
    // MARK: - Model Tests
    
    func testScannedFileModel() {
        let file = ScannedFile(
            path: "/test/image.jpg",
            fileName: "image.jpg",
            fileSize: 2048,
            fileType: "public.jpeg"
        )
        
        XCTAssertEqual(file.fileName, "image.jpg")
        XCTAssertEqual(file.fileSize, 2048)
        XCTAssertEqual(file.formattedFileSize, "2 KB")
        XCTAssertTrue(file.isImage)
        XCTAssertFalse(file.isVideo)
    }
    
    func testDuplicateGroupModel() {
        let group = DuplicateGroup(sha256Hash: "test123", fileSize: 1024)
        
        let file1 = ScannedFile(path: "/test/file1.jpg", fileName: "file1.jpg", fileSize: 1024, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/file2.jpg", fileName: "file2.jpg", fileSize: 1024, fileType: "public.jpeg")
        
        file1.creationDate = Date(timeIntervalSince1970: 1000)
        file2.creationDate = Date(timeIntervalSince1970: 2000)
        
        group.files = [file1, file2]
        
        XCTAssertEqual(group.fileCount, 2)
        XCTAssertEqual(group.potentialSpaceSaved, 1024)
        XCTAssertEqual(group.oldestFile?.fileName, "file1.jpg")
        XCTAssertEqual(group.newestFile?.fileName, "file2.jpg")
    }
    
    // MARK: - DataActor Tests
    
    func testDataActorSessionCreation() async throws {
        let session = await dataActor.createSession(scanPath: "/test/path")
        
        XCTAssertEqual(session.scanPath, "/test/path")
        XCTAssertEqual(session.status, .scanning)
        XCTAssertNotNil(session.id)
    }
    
    func testDataActorFileCreation() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("test1.jpg")
        let url2 = testDir.appendingPathComponent("test2.jpg")
        
        try createTestFile(at: url1)
        try createTestFile(at: url2)
        
        // Create a session first
        let session = await dataActor.createSession(scanPath: testDir.path)
        let files = try await dataActor.createScannedFiles(from: [url1, url2], sessionID: session.id)
        
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].fileName, "test1.jpg")
        XCTAssertEqual(files[1].fileName, "test2.jpg")
    }
    
    // MARK: - Organization Tests
    
    func testFolderOrganization() {
        let organizer = FolderOrganizer()
        let testDate = DateComponents(calendar: .current, year: 2023, month: 8, day: 15).date!
        
        let file = ScannedFile(
            path: "/source/IMG_1234.jpg",
            fileName: "IMG_1234.jpg",
            fileSize: 1000,
            fileType: "public.jpeg"
        )
        file.originalCreationDate = testDate
        
        let destPath = organizer.generateOrganizedPath(
            for: file,
            baseURL: URL(fileURLWithPath: "/dest"),
            organizationMode: .yearMonth,
            namingMode: .keepOriginal
        )
        
        XCTAssertTrue(destPath.path.contains("2023"))
        XCTAssertTrue(destPath.path.contains("08"))
        XCTAssertTrue(destPath.lastPathComponent == "IMG_1234.jpg")
    }
    
    func testDatePrefixNaming() {
        let organizer = FolderOrganizer()
        let testDate = DateComponents(calendar: .current, year: 2023, month: 8, day: 15, hour: 14, minute: 30).date!
        
        let file = ScannedFile(
            path: "/source/photo.jpg",
            fileName: "photo.jpg",
            fileSize: 1000,
            fileType: "public.jpeg"
        )
        file.originalCreationDate = testDate
        
        let destPath = organizer.generateOrganizedPath(
            for: file,
            baseURL: URL(fileURLWithPath: "/dest"),
            organizationMode: .yearMonth,
            namingMode: .datePrefix
        )
        
        XCTAssertTrue(destPath.lastPathComponent.hasPrefix("2023-08-15_14-30"))
        XCTAssertTrue(destPath.lastPathComponent.hasSuffix("photo.jpg"))
    }
    
    // MARK: - Performance Tests
    
    func testLargeScalePerformance() async throws {
        // Test with 10,000 files
        measure {
            let expectation = XCTestExpectation(description: "Large scale test")
            
            Task {
                let scanner = FileScanner()
                let testDir = createTestDirectory()
                defer { try? FileManager.default.removeItem(at: testDir) }
                
                // Create many test files
                for i in 0..<10000 {
                    let url = testDir.appendingPathComponent("file\(i).jpg")
                    try? createTestFile(at: url)
                }
                
                // Measure scanning performance
                let urls = try? await scanner.scanDirectory(at: testDir, scanAllTypes: true)
                XCTAssertEqual(urls?.count, 10000)
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 60)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostRecoveryXTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createTestFile(at url: URL, content: String = "test") throws {
        try content.data(using: .utf8)?.write(to: url)
    }
}

// MARK: - Image Processing Tests

final class ImageProcessingTests: XCTestCase {
    
    func testPerceptualHashGeneration() async throws {
        let hasher = ImageHasher()
        
        // Create a test image
        let testImage = createTestImage(color: .red)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_image.jpg")
        
        try testImage.jpegData(compressionQuality: 0.8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let hash = try await hasher.computePerceptualHash(for: tempURL)
        
        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.hash.count, 16) // 64-bit hash = 16 hex characters
    }
    
    func testSimilarImageDetection() async throws {
        let hasher = ImageHasher()
        
        // Create two similar images
        let image1 = createTestImage(color: .red)
        let image2 = createTestImage(color: NSColor(red: 0.9, green: 0, blue: 0, alpha: 1))
        
        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("image1.jpg")
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("image2.jpg")
        
        try image1.jpegData(compressionQuality: 0.8)?.write(to: url1)
        try image2.jpegData(compressionQuality: 0.8)?.write(to: url2)
        
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let hash1 = try await hasher.computePerceptualHash(for: url1)
        let hash2 = try await hasher.computePerceptualHash(for: url2)
        
        XCTAssertNotNil(hash1)
        XCTAssertNotNil(hash2)
        
        // Should be similar but not identical
        let matchResult = hash1!.matches(hash2!, threshold: 5)
        XCTAssertTrue(matchResult.matches, "Similar images should match with threshold")
    }
    
    private func createTestImage(color: NSColor, size: CGSize = CGSize(width: 100, height: 100)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - Integration Tests

final class IntegrationTests: XCTestCase {
    
    func testFullScanWorkflow() async throws {
        // This test simulates a complete scan workflow
        let modelContainer = try ModelContainer(
            for: Schema([
                ScannedFile.self,
                DuplicateGroup.self,
                OrganizationTask.self,
                ScanSession.self,
                SimilarSceneGroup.self
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        
        let dataActor = DataActor(modelContainer: modelContainer)
        let viewModel = MainViewModel()
        viewModel.setModelContext(modelContainer.mainContext)
        
        // Create test directory
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntegrationTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        for i in 0..<10 {
            let content = "Test file \(i % 3)" // Create some duplicates
            try content.data(using: .utf8)?.write(to: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        // Set scan path
        viewModel.scanPath = testDir.path
        viewModel.scanAllFileTypes = true
        
        // Start scan
        await viewModel.startScan()
        
        // Wait for scan to complete
        while viewModel.isScanning {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Verify results (session is tracked via currentSessionID)
        XCTAssertNotNil(viewModel.currentSessionID)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertEqual(viewModel.currentPhase, .complete)
    }
}
