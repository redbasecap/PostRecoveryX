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
        let baseSize = 500
        let scaleFactor = max(1, processorCount)
        return min(5000, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for metadata parsing
    var metadataParsingBatchSize: Int {
        // Metadata parsing is I/O intensive, but we can handle more
        let baseSize = 100
        let scaleFactor = max(1, processorCount / 2)
        return min(500, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for duplicate detection
    var duplicateDetectionBatchSize: Int {
        // Hash computation is CPU intensive but we can optimize
        let baseSize = 50
        let scaleFactor = max(1, processorCount)
        return min(500, baseSize * scaleFactor)
    }
    
    /// Optimal batch size for database operations
    var databaseBatchSize: Int {
        // Database operations benefit from much larger batches
        let baseSize = 2000
        let memoryFactor = physicalMemory > 8_000_000_000 ? 3 : 2 // 8GB threshold
        return min(10000, baseSize * memoryFactor)
    }
    
    /// Maximum concurrent tasks based on system capabilities
    var maxConcurrentTasks: Int {
        // More aggressive concurrency for better performance
        max(4, min(processorCount * 2, 16))
    }
    
    /// Scene detection chunk size for parallel processing
    var sceneDetectionChunkSize: Int {
        let baseSize = 1000
        let scaleFactor = max(1, processorCount)
        return min(5000, baseSize * scaleFactor)
    }
    
    /// Whether to use high-performance mode based on system resources
    var isHighPerformanceMode: Bool {
        processorCount >= 4 && physicalMemory >= 8_000_000_000 // 4+ cores and 8GB+ RAM
    }
    
    /// Optimal number of concurrent file I/O operations
    var maxConcurrentFileOperations: Int {
        // Modern SSDs can handle much more concurrent I/O
        isHighPerformanceMode ? 50 : 25
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