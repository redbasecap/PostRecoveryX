import Foundation

/// Performance configuration that adapts to system capabilities
struct PerformanceConfiguration {
    static let shared = PerformanceConfiguration()
    
    private init() {}
    
    /// Number of processor cores available
    var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }
    
    /// Available physical memory in bytes
    var physicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }
    
    /// Optimal batch size for file scanning based on system capabilities
    var fileScanningBatchSize: Int {
        let baseSize = 100
        let scaleFactor = max(1, processorCount / 2)
        return min(1000, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for metadata parsing
    var metadataParsingBatchSize: Int {
        // Metadata parsing is I/O intensive, use smaller batches
        let baseSize = 20
        let scaleFactor = max(1, processorCount / 4)
        return min(100, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for duplicate detection
    var duplicateDetectionBatchSize: Int {
        // Hash computation is CPU intensive
        let baseSize = 10
        let scaleFactor = max(1, processorCount / 2)
        return min(50, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for database operations
    var databaseBatchSize: Int {
        // Database operations benefit from larger batches
        let baseSize = 500
        let memoryFactor = physicalMemory > 8_000_000_000 ? 2 : 1 // 8GB threshold
        return min(2000, baseSize * memoryFactor)
    }
    
    /// Maximum concurrent tasks based on system capabilities
    var maxConcurrentTasks: Int {
        // Conservative approach to avoid overwhelming the system
        max(2, min(processorCount, 8))
    }
    
    /// Scene detection chunk size for parallel processing
    var sceneDetectionChunkSize: Int {
        let baseSize = 200
        let scaleFactor = max(1, processorCount / 2)
        return min(1000, baseSize * scaleFactor)
    }
    
    /// Whether to use high-performance mode based on system resources
    var isHighPerformanceMode: Bool {
        processorCount >= 8 && physicalMemory >= 16_000_000_000 // 8+ cores and 16GB+ RAM
    }
    
    /// Optimal number of concurrent file I/O operations
    var maxConcurrentFileOperations: Int {
        // File I/O is limited by storage speed, not CPU
        isHighPerformanceMode ? 20 : 10
    }
    
    /// Memory threshold for triggering garbage collection hints
    var memoryPressureThreshold: Double {
        Double(physicalMemory) * 0.8 // 80% of available memory
    }
    
    /// Print current configuration for debugging
    func printConfiguration() {
        print("""
        Performance Configuration:
        - Processor Count: \(processorCount)
        - Physical Memory: \(ByteCountFormatter.string(fromByteCount: Int64(physicalMemory), countStyle: .memory))
        - High Performance Mode: \(isHighPerformanceMode)
        - File Scanning Batch Size: \(fileScanningBatchSize)
        - Metadata Parsing Batch Size: \(metadataParsingBatchSize)
        - Duplicate Detection Batch Size: \(duplicateDetectionBatchSize)
        - Database Batch Size: \(databaseBatchSize)
        - Max Concurrent Tasks: \(maxConcurrentTasks)
        - Scene Detection Chunk Size: \(sceneDetectionChunkSize)
        - Max Concurrent File Operations: \(maxConcurrentFileOperations)
        """)
    }
}