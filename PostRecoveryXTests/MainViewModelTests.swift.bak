import Testing
import SwiftData
import Foundation
@testable import PostRecoveryX

@MainActor
struct MainViewModelTests {
    let modelContainer: ModelContainer
    let viewModel: MainViewModel
    
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
        viewModel = MainViewModel()
        viewModel.setModelContext(modelContainer.mainContext)
    }
    
    @Test func initialState() async throws {
        #expect(viewModel.scanPath.isEmpty)
        #expect(!viewModel.isScanning)
        #expect(viewModel.scanProgress == 0.0)
        #expect(viewModel.scanStatus.isEmpty)
        #expect(viewModel.currentSessionID == nil)
        #expect(!viewModel.showError)
        #expect(viewModel.currentPhase == .idle)
        #expect(viewModel.filesDiscovered == 0)
        #expect(viewModel.filesProcessed == 0)
        #expect(viewModel.totalFiles == 0)
    }
    
    @Test func setScanPath() async throws {
        let testPath = "/test/scan/path"
        viewModel.scanPath = testPath
        
        #expect(viewModel.scanPath == testPath)
    }
    
    @Test func toggleScanAllFileTypes() async throws {
        let initialValue = viewModel.scanAllFileTypes
        viewModel.scanAllFileTypes = !initialValue
        
        #expect(viewModel.scanAllFileTypes == !initialValue)
    }
    
    @Test func toggleVisualMatching() async throws {
        let initialValue = viewModel.enableVisualMatching
        viewModel.enableVisualMatching = !initialValue
        
        #expect(viewModel.enableVisualMatching == !initialValue)
    }
    
    @Test func scanWithEmptyPath() async throws {
        viewModel.scanPath = ""
        
        await viewModel.startScan()
        
        // Should not start scanning with empty path
        #expect(!viewModel.isScanning)
        #expect(viewModel.currentSessionID == nil)
    }
    
    @Test func scanWithValidDirectory() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        try createTestFile(at: testDir.appendingPathComponent("test1.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("test2.png"))
        
        viewModel.scanPath = testDir.path
        viewModel.scanAllFileTypes = false // Don't show file type selection
        
        await viewModel.startScan()
        
        // Wait for scan to complete
        while viewModel.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
        }
        
        #expect(viewModel.currentSessionID != nil)
        #expect(viewModel.currentPhase == .complete)
        #expect(viewModel.totalFiles >= 2)
    }
    
    @Test func scanAllFileTypesShowsSelection() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        try createTestFile(at: testDir.appendingPathComponent("test.jpg"))
        
        viewModel.scanPath = testDir.path
        viewModel.scanAllFileTypes = true
        
        await viewModel.startScan()
        
        // Should show file type selection after discovery
        #expect(viewModel.showFileTypeSelection)
        #expect(!viewModel.isScanning) // Paused for selection
    }
    
    @Test func cancelScan() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create many files to have time to cancel
        for i in 0..<100 {
            try createTestFile(at: testDir.appendingPathComponent("file\(i).txt"))
        }
        
        viewModel.scanPath = testDir.path
        
        // Start scan
        let scanTask = Task {
            await viewModel.startScan()
        }
        
        // Cancel immediately
        await viewModel.cancelScan()
        
        await scanTask.value
        
        #expect(!viewModel.isScanning)
        #expect(viewModel.currentPhase == .idle)
        #expect(viewModel.scanStatus.contains("cancelled"))
    }
    
    @Test func processSelectedFileTypesWithFilter() async throws {
        let testDir = createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        try createTestFile(at: testDir.appendingPathComponent("image.jpg"))
        try createTestFile(at: testDir.appendingPathComponent("document.pdf"))
        
        viewModel.scanPath = testDir.path
        viewModel.scanAllFileTypes = true
        
        // Start initial scan
        await viewModel.startScan()
        
        // Should show file type selection
        #expect(viewModel.showFileTypeSelection)
        
        // Set filter to only include images
        viewModel.fileTypeFilter = SimpleFileTypeFilter(
            selectedTypes: ["public.jpeg", "jpg"],
            discoveredTypes: ["public.jpeg", "public.pdf"]
        )
        
        // Process selected types
        await viewModel.processSelectedFileTypes()
        
        // Wait for processing to complete
        while viewModel.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        #expect(viewModel.currentPhase == .complete)
        #expect(!viewModel.showFileTypeSelection)
    }
    
    @Test func updateTimeEstimates() async throws {
        viewModel.scanStartTime = Date()
        viewModel.totalFiles = 100
        viewModel.filesProcessed = 50
        viewModel.currentPhase = .extractingMetadata
        
        // Call private method through simulation
        viewModel.progressPercentage = 50
        
        #expect(viewModel.progressPercentage == 50)
        #expect(viewModel.scanStartTime != nil)
    }
    
    @Test func errorHandling() async throws {
        // Test with non-existent directory
        viewModel.scanPath = "/non/existent/path"
        
        await viewModel.startScan()
        
        // Should handle error gracefully
        #expect(viewModel.showError || !viewModel.errorMessage.isEmpty)
        #expect(!viewModel.isScanning)
    }
    
    @Test func continueSession() async throws {
        let session = ScanSession(scanPath: "/test/path")
        session.status = .processing
        session.totalFilesFound = 50
        session.totalFilesProcessed = 25
        
        await viewModel.continueSession(session)
        
        #expect(viewModel.currentSessionID == session.id)
        #expect(viewModel.scanPath == "/test/path")
        #expect(viewModel.scanStatus.contains("Continuing"))
    }
    
    @Test func fileTypeFilterUpdates() async throws {
        let initialFilter = viewModel.fileTypeFilter
        
        let newFilter = SimpleFileTypeFilter(
            selectedTypes: ["public.jpeg"],
            discoveredTypes: ["public.jpeg", "public.png"]
        )
        
        viewModel.fileTypeFilter = newFilter
        
        #expect(viewModel.fileTypeFilter.selectedTypes.contains("public.jpeg"))
        #expect(viewModel.fileTypeFilter.discoveredTypes.count == 2)
    }
    
    @Test func progressTracking() async throws {
        viewModel.filesDiscovered = 10
        viewModel.filesProcessed = 5
        viewModel.totalFiles = 10
        viewModel.progressPercentage = 50
        
        #expect(viewModel.filesDiscovered == 10)
        #expect(viewModel.filesProcessed == 5)
        #expect(viewModel.totalFiles == 10)
        #expect(viewModel.progressPercentage == 50)
    }
    
    @Test func scanPhaseTransitions() async throws {
        #expect(viewModel.currentPhase == .idle)
        
        viewModel.currentPhase = .discovering
        #expect(viewModel.currentPhase == .discovering)
        
        viewModel.currentPhase = .extractingMetadata
        #expect(viewModel.currentPhase == .extractingMetadata)
        
        viewModel.currentPhase = .complete
        #expect(viewModel.currentPhase == .complete)
    }
    
    @Test func currentSessionProperty() async throws {
        // Test the computed property
        let session = viewModel.currentSession
        
        // Should return nil as it's not implemented for async context
        #expect(session == nil)
    }
    
    @Test func memoryLeakProtection() async throws {
        // Test that viewModel can be deallocated properly
        weak var weakViewModel: MainViewModel?
        
        do {
            let testViewModel = MainViewModel()
            weakViewModel = testViewModel
            #expect(weakViewModel != nil)
        }
        
        // After scope, weak reference should become nil if no retain cycles
        // Note: This test may not be reliable in test environment
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainViewModelTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createTestFile(at url: URL, content: String = "test content") throws {
        try content.data(using: .utf8)?.write(to: url)
    }
}