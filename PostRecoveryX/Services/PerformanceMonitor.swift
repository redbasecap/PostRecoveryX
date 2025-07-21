import Foundation
import Combine
import os

@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var metrics = PerformanceMetrics()
    @Published var isMonitoring = false
    @Published var currentSnapshot: PerformanceSnapshot?
    
    private var timer: Timer?
    private var startTime: Date?
    private var lastFileCount: Int = 0
    private var lastTimestamp: Date = Date()
    private var processInfo = ProcessInfo.processInfo
    private let logger = Logger(subsystem: "PostRecoveryX", category: "Performance")
    
    // Performance counters
    private var filesProcessed: Int = 0
    private var bytesProcessed: Int64 = 0
    private var operationStartTimes: [String: Date] = [:]
    private var operationCounts: [String: Int] = [:]
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        metrics = PerformanceMetrics(sessionStartTime: Date())
        
        // Start periodic sampling
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectMetrics()
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        
        // Log final statistics
        logSessionStatistics()
    }
    
    func recordFileProcessed(size: Int64 = 0) {
        filesProcessed += 1
        bytesProcessed += size
        metrics.totalFilesProcessed = filesProcessed
        metrics.totalBytesProcessed = bytesProcessed
    }
    
    func recordOperationStart(_ operation: String) {
        operationStartTimes[operation] = Date()
    }
    
    func recordOperationComplete(_ operation: String) {
        guard let startTime = operationStartTimes[operation] else { return }
        let duration = Date().timeIntervalSince(startTime)
        
        operationCounts[operation, default: 0] += 1
        
        logger.debug("Operation '\(operation)' completed in \(duration)s")
    }
    
    private func collectMetrics() {
        let currentTime = Date()
        let timeDelta = currentTime.timeIntervalSince(lastTimestamp)
        
        // Calculate files per second
        let filesPerSecond = timeDelta > 0 ? Double(filesProcessed - lastFileCount) / timeDelta : 0
        
        // Get system metrics
        let cpuUsage = getCPUUsage()
        let memoryUsage = getMemoryUsage()
        let diskUsage = getDiskUsage()
        
        // Detect current operation
        let currentOp = detectCurrentOperation()
        
        let snapshot = PerformanceSnapshot(
            timestamp: currentTime,
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            filesProcessedPerSecond: filesPerSecond,
            currentOperation: currentOp,
            queueDepth: getQueueDepth()
        )
        
        metrics.addSnapshot(snapshot)
        currentSnapshot = snapshot
        
        // Update counters
        lastFileCount = filesProcessed
        lastTimestamp = currentTime
        
        // Log if performance issues detected
        if let bottleneck = metrics.currentBottleneck, bottleneck.severity == .high {
            logger.warning("Performance bottleneck detected: \(bottleneck.description)")
        }
    }
    
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            // This gives us thread time, we need to calculate percentage
            let totalTime = info.user_time.totalSeconds + info.system_time.totalSeconds
            let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
            return elapsedTime > 0 ? min(totalTime / elapsedTime, 1.0) : 0
        }
        
        return 0
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size)
        }
        
        return 0
    }
    
    private func getDiskUsage() -> Double {
        // For now, return bytes processed as disk usage
        // In a real implementation, we'd track actual disk I/O
        return Double(bytesProcessed)
    }
    
    private func getQueueDepth() -> Int {
        // This would be implemented based on actual queue monitoring
        // For now, return a placeholder
        return 0
    }
    
    private func detectCurrentOperation() -> String {
        // Find the most recent operation
        let recentOps = operationStartTimes.filter { 
            $0.value.timeIntervalSinceNow > -5 // Operations started in last 5 seconds
        }
        
        return recentOps.sorted { $0.value > $1.value }.first?.key ?? "Idle"
    }
    
    private func logSessionStatistics() {
        guard let startTime = startTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let averageSpeed = duration > 0 ? Double(filesProcessed) / duration : 0
        
        logger.info("""
        Performance Session Summary:
        - Duration: \(String(format: "%.1f", duration))s
        - Files Processed: \(self.filesProcessed)
        - Bytes Processed: \(ByteCountFormatter.string(fromByteCount: self.bytesProcessed, countStyle: .file))
        - Average Speed: \(String(format: "%.1f", averageSpeed)) files/s
        - Peak CPU: \(String(format: "%.1f%%", self.metrics.peakCPUUsage * 100))
        - Peak Memory: \(ByteCountFormatter.string(fromByteCount: Int64(self.metrics.peakMemoryUsage), countStyle: .memory))
        - Bottlenecks: \(self.metrics.bottlenecks.count)
        """)
    }
    
    func estimateTimeRemaining(totalFiles: Int) -> TimeInterval? {
        guard filesProcessed > 0, metrics.averageFilesPerSecond > 0 else { return nil }
        
        let remainingFiles = totalFiles - filesProcessed
        return Double(remainingFiles) / metrics.averageFilesPerSecond
    }
}

// Extension for time_value_t
extension time_value_t {
    var totalSeconds: Double {
        return Double(self.seconds) + Double(self.microseconds) / 1_000_000.0
    }
}