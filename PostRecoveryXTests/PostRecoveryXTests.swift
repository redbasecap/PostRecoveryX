//
//  PostRecoveryXTests.swift
//  PostRecoveryXTests
//
//  Created by Nicola Spieser on 10.07.2025.
//

import Testing
import SwiftData
import Foundation
import AppKit
@testable import PostRecoveryX

struct PostRecoveryXTests {
    
    @MainActor
    static func createTestContainer() throws -> (ModelContainer, ModelContext, DataActor) {
        // Create in-memory container for testing
        let schema = Schema([
            ScannedFile.self,
            DuplicateGroup.self,
            OrganizationTask.self,
            ScanSession.self,
            PerformanceData.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let modelContext = modelContainer.mainContext
        let dataActor = DataActor(modelContainer: modelContainer)
        
        return (modelContainer, modelContext, dataActor)
    }
    
    // MARK: - File Scanner Tests
    
    @Test func fileScannerDiscovery() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        try createTestFile(at: testDir.appendingPathComponent("test1.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("test2.png"))
        try createTestFile(at: testDir.appendingPathComponent("test3.txt"))
        
        // Scan directory
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: true)
        
        #expect(urls.count == 3)
    }
    
    @Test func fileScannerImageOnlyMode() async throws {
        let scanner = FileScanner()
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        try createTestFile(at: testDir.appendingPathComponent("test1.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("test2.png"))
        try createTestFile(at: testDir.appendingPathComponent("test3.txt"))
        
        // Scan directory - image only mode
        let urls = try await scanner.scanDirectory(at: testDir, scanAllTypes: false)
        
        #expect(urls.count == 2)
    }
    
    // MARK: - Duplicate Detection Tests
    
    @Test func exactDuplicateDetection() async throws {
        let (_, modelContext, dataActor) = try await MainActor.run {
            try Self.createTestContainer()
        }
        let duplicateChecker = DuplicateChecker()
        
        // Create test files with same content
        let file1 = ScannedFile(path: "/test/file1.jpg", fileName: "file1.jpg", fileSize: 1000, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/file2.jpg", fileName: "file2.jpg", fileSize: 1000, fileType: "public.jpeg")
        
        // Mock same hash
        file1.sha256Hash = "abc123"
        file2.sha256Hash = "abc123"
        
        // Create a session first
        let session = await dataActor.createSession(scanPath: "/test")
        let _ = try await dataActor.createScannedFiles(from: [], sessionID: session.id)
        
        // Manually insert our test files
        modelContext.insert(file1)
        modelContext.insert(file2)
        try modelContext.save()
        
        let groups = try await duplicateChecker.findDuplicates(
            in: [file1, file2],
            modelContext: modelContext,
            enableVisualMatching: false
        )
        
        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 2)
    }
    
    // MARK: - Model Tests
    
    @Test func scannedFileModel() {
        let file = ScannedFile(
            path: "/test/image.jpg",
            fileName: "image.jpg",
            fileSize: 2048,
            fileType: "public.jpeg"
        )
        
        #expect(file.fileName == "image.jpg")
        #expect(file.fileSize == 2048)
        #expect(file.formattedFileSize == "2 KB")
        #expect(file.fileType == "public.jpeg")
    }
    
    @Test func duplicateGroupModel() {
        let group = DuplicateGroup(sha256Hash: "test123", fileSize: 1024)
        
        let file1 = ScannedFile(path: "/test/file1.jpg", fileName: "file1.jpg", fileSize: 1024, fileType: "public.jpeg")
        let file2 = ScannedFile(path: "/test/file2.jpg", fileName: "file2.jpg", fileSize: 1024, fileType: "public.jpeg")
        
        file1.creationDate = Date(timeIntervalSince1970: 1000)
        file2.creationDate = Date(timeIntervalSince1970: 2000)
        
        group.files = [file1, file2]
        
        #expect(group.fileCount == 2)
        #expect(group.potentialSpaceSaved == 1024)
        #expect(group.oldestFile?.fileName == "file1.jpg")
        #expect(group.newestFile?.fileName == "file2.jpg")
    }
    
    // MARK: - DataActor Tests
    
    @Test func dataActorSessionCreation() async throws {
        let (_, _, dataActor) = try await MainActor.run {
            try Self.createTestContainer()
        }
        let session = await dataActor.createSession(scanPath: "/test/path")
        
        #expect(session.scanPath == "/test/path")
        #expect(session.status == .scanning)
        #expect(session.id != UUID())
    }
    
    @Test func dataActorFileCreation() async throws {
        let (_, _, dataActor) = try await MainActor.run {
            try Self.createTestContainer()
        }
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let url1 = testDir.appendingPathComponent("test1.jpg")
        let url2 = testDir.appendingPathComponent("test2.jpg")
        
        try createTestFile(at: url1)
        try createTestFile(at: url2)
        
        // Create a session first
        let session = await dataActor.createSession(scanPath: testDir.path)
        let files = try await dataActor.createScannedFiles(from: [url1, url2], sessionID: session.id)
        
        #expect(files.count == 2)
        #expect(files[0].fileName == "test1.jpg")
        #expect(files[1].fileName == "test2.jpg")
    }
    
    // MARK: - Organization Tests
    
    @Test func scannedFileOrganizationPath() {
        let testDate = DateComponents(calendar: .current, year: 2023, month: 8, day: 15).date!
        
        let file = ScannedFile(
            path: "/source/topfolder/IMG_1234.jpg",
            fileName: "IMG_1234.jpg",
            fileSize: 1000,
            fileType: "public.jpeg"
        )
        file.originalCreationDate = testDate
        
        let suggestedPath = file.suggestedOrganizationPath
        
        #expect(suggestedPath != nil)
        #expect(suggestedPath?.contains("2023") == true)
        #expect(suggestedPath?.contains("08") == true)
        #expect(suggestedPath?.contains("topfolder") == true)
    }
    
    @Test func metadataQualityScore() {
        let file = ScannedFile(
            path: "/test/photo.jpg",
            fileName: "photo.jpg",
            fileSize: 5_500_000, // 5.5MB
            fileType: "public.jpeg"
        )
        
        file.originalCreationDate = Date()
        file.cameraModel = "iPhone 12"
        file.width = 4000
        file.height = 3000
        file.hasMetadata = true
        
        let score = file.metadataQualityScore
        
        // Base (10) + originalCreationDate (30) + cameraModel (20) + highRes (15) + hasMetadata (10) + largeFile (10) = 95
        #expect(score == 95)
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

struct ImageProcessingTests {
    
    @Test func perceptualHashGeneration() async throws {
        let hasher = ImageHasher()
        
        // Create a test image
        let testImage = createTestImage(color: .red)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_image.jpg")
        
        let imageRep = NSBitmapImageRep(data: testImage.tiffRepresentation!)
        let jpegData = imageRep?.representation(using: .jpeg, properties: [:])
        try jpegData?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let hash = try await hasher.computePerceptualHash(for: tempURL)
        
        #expect(hash != nil)
        #expect(hash != nil)
        #expect(hash?.hash != nil) // 64-bit hash exists
    }
    
    @Test func similarImageDetection() async throws {
        let hasher = ImageHasher()
        
        // Create two similar images
        let image1 = createTestImage(color: .red)
        let image2 = createTestImage(color: NSColor(red: 0.9, green: 0, blue: 0, alpha: 1))
        
        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("image1.jpg")
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("image2.jpg")
        
        let imageRep1 = NSBitmapImageRep(data: image1.tiffRepresentation!)
        let jpegData1 = imageRep1?.representation(using: .jpeg, properties: [:])
        try jpegData1?.write(to: url1)
        
        let imageRep2 = NSBitmapImageRep(data: image2.tiffRepresentation!)
        let jpegData2 = imageRep2?.representation(using: .jpeg, properties: [:])
        try jpegData2?.write(to: url2)
        
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let hash1 = try await hasher.computePerceptualHash(for: url1)
        let hash2 = try await hasher.computePerceptualHash(for: url2)
        
        #expect(hash1 != nil)
        #expect(hash2 != nil)
        
        // Should be similar but not identical
        let matchResult = hash1!.matches(hash2!, threshold: 5)
        #expect(matchResult.matches)
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

struct IntegrationTests {
    
    @Test func fullScanWorkflow() async throws {
        // This test simulates a complete scan workflow
        let modelContainer = try ModelContainer(
            for: Schema([
                ScannedFile.self,
                DuplicateGroup.self,
                OrganizationTask.self,
                ScanSession.self,
                PerformanceData.self
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        
        let dataActor = DataActor(modelContainer: modelContainer)
        let viewModel = await MainViewModel()
        let context = await MainActor.run { modelContainer.mainContext }
        await viewModel.setModelContext(context)
        
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
        await MainActor.run {
            viewModel.scanPath = testDir.path
            viewModel.scanAllFileTypes = true
        }
        
        // Start scan
        await viewModel.startScan()
        
        // Wait for scan to complete
        while await viewModel.isScanning {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Verify results
        let sessionID = await viewModel.currentSessionID
        let isScanning = await viewModel.isScanning
        let phase = await viewModel.currentPhase
        
        #expect(sessionID != nil)
        #expect(!isScanning)
        #expect(phase == .complete)
    }
}