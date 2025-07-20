import Foundation
import SwiftData

@Model
final class PerformanceData {
    var timestamp: Date
    var cpuUsage: Double
    var memoryUsage: Double
    var diskUsage: Double
    var filesProcessedPerSecond: Double
    var currentOperation: String
    var queueDepth: Int
    var averageFileProcessingTime: Double
    var peakMemoryUsage: Double
    var totalBytesProcessed: Int64
    
    init(
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsage: Double = 0,
        diskUsage: Double = 0,
        filesProcessedPerSecond: Double = 0,
        currentOperation: String = "",
        queueDepth: Int = 0,
        averageFileProcessingTime: Double = 0,
        peakMemoryUsage: Double = 0,
        totalBytesProcessed: Int64 = 0
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.filesProcessedPerSecond = filesProcessedPerSecond
        self.currentOperation = currentOperation
        self.queueDepth = queueDepth
        self.averageFileProcessingTime = averageFileProcessingTime
        self.peakMemoryUsage = peakMemoryUsage
        self.totalBytesProcessed = totalBytesProcessed
    }
}

struct PerformanceSnapshot {
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let diskUsage: Double
    let filesProcessedPerSecond: Double
    let currentOperation: String
    let queueDepth: Int
    
    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage * 100)
    }
    
    var formattedMemory: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(memoryUsage))
    }
    
    var formattedDisk: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(diskUsage))
    }
    
    var formattedFilesPerSecond: String {
        String(format: "%.1f files/s", filesProcessedPerSecond)
    }
}

struct PerformanceMetrics {
    var snapshots: [PerformanceSnapshot] = []
    var bottlenecks: [Bottleneck] = []
    var sessionStartTime: Date = Date()
    var totalFilesProcessed: Int = 0
    var totalBytesProcessed: Int64 = 0
    
    mutating func addSnapshot(_ snapshot: PerformanceSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > 300 { // Keep last 5 minutes at 1 sample/second
            snapshots.removeFirst()
        }
        
        // Detect bottlenecks
        detectBottlenecks(from: snapshot)
    }
    
    private mutating func detectBottlenecks(from snapshot: PerformanceSnapshot) {
        // CPU bottleneck
        if snapshot.cpuUsage > 0.9 {
            bottlenecks.append(Bottleneck(
                type: .cpu,
                severity: .high,
                timestamp: snapshot.timestamp,
                description: "CPU usage above 90%"
            ))
        }
        
        // Memory pressure
        if snapshot.memoryUsage > Double(ProcessInfo.processInfo.physicalMemory) * 0.8 {
            bottlenecks.append(Bottleneck(
                type: .memory,
                severity: .high,
                timestamp: snapshot.timestamp,
                description: "Memory usage above 80% of available RAM"
            ))
        }
        
        // Processing speed
        if snapshot.filesProcessedPerSecond < 1.0 && snapshot.filesProcessedPerSecond > 0 {
            bottlenecks.append(Bottleneck(
                type: .processingSpeed,
                severity: .medium,
                timestamp: snapshot.timestamp,
                description: "Processing less than 1 file per second"
            ))
        }
        
        // Queue depth
        if snapshot.queueDepth > 1000 {
            bottlenecks.append(Bottleneck(
                type: .queueDepth,
                severity: .medium,
                timestamp: snapshot.timestamp,
                description: "Large queue depth may indicate I/O bottleneck"
            ))
        }
    }
    
    var averageFilesPerSecond: Double {
        guard !snapshots.isEmpty else { return 0 }
        let sum = snapshots.reduce(0) { $0 + $1.filesProcessedPerSecond }
        return sum / Double(snapshots.count)
    }
    
    var peakCPUUsage: Double {
        snapshots.map { $0.cpuUsage }.max() ?? 0
    }
    
    var peakMemoryUsage: Double {
        snapshots.map { $0.memoryUsage }.max() ?? 0
    }
    
    var currentBottleneck: Bottleneck? {
        bottlenecks.last
    }
}

struct Bottleneck {
    enum BottleneckType {
        case cpu
        case memory
        case disk
        case processingSpeed
        case queueDepth
    }
    
    enum Severity {
        case low
        case medium
        case high
    }
    
    let type: BottleneckType
    let severity: Severity
    let timestamp: Date
    let description: String
}