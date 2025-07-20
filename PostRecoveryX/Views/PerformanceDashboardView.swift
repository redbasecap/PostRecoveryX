import SwiftUI
import Charts

struct PerformanceDashboardView: View {
    @StateObject private var monitor = PerformanceMonitor.shared
    @State private var selectedMetric: MetricType = .cpu
    @Environment(\.dismiss) private var dismiss
    
    enum MetricType: String, CaseIterable {
        case cpu = "CPU Usage"
        case memory = "Memory Usage"
        case filesPerSecond = "Processing Speed"
        case diskIO = "Disk I/O"
        
        var icon: String {
            switch self {
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .filesPerSecond: return "speedometer"
            case .diskIO: return "internaldrive"
            }
        }
        
        var color: Color {
            switch self {
            case .cpu: return .blue
            case .memory: return .green
            case .filesPerSecond: return .orange
            case .diskIO: return .purple
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Performance Monitor", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                if monitor.isMonitoring {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Monitoring")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Main content
            HSplitView {
                // Left panel - Current metrics
                VStack(alignment: .leading, spacing: 16) {
                    Text("Current Metrics")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if let snapshot = monitor.currentSnapshot {
                        MetricCard(
                            title: "CPU Usage",
                            value: snapshot.formattedCPU,
                            icon: "cpu",
                            color: .blue,
                            progress: snapshot.cpuUsage
                        )
                        
                        MetricCard(
                            title: "Memory Usage",
                            value: snapshot.formattedMemory,
                            icon: "memorychip",
                            color: .green,
                            progress: snapshot.memoryUsage / Double(ProcessInfo.processInfo.physicalMemory)
                        )
                        
                        MetricCard(
                            title: "Processing Speed",
                            value: snapshot.formattedFilesPerSecond,
                            icon: "speedometer",
                            color: .orange,
                            progress: min(snapshot.filesProcessedPerSecond / 100, 1.0)
                        )
                        
                        MetricCard(
                            title: "Queue Depth",
                            value: "\(snapshot.queueDepth) files",
                            icon: "tray.full",
                            color: .purple,
                            progress: min(Double(snapshot.queueDepth) / 1000, 1.0)
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Current Operation", systemImage: "gearshape")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(snapshot.currentOperation)
                                .font(.headline)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Session statistics
                    if monitor.metrics.totalFilesProcessed > 0 {
                        GroupBox("Session Statistics") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Files Processed:")
                                    Spacer()
                                    Text("\(monitor.metrics.totalFilesProcessed)")
                                        .bold()
                                }
                                
                                HStack {
                                    Text("Data Processed:")
                                    Spacer()
                                    Text(ByteCountFormatter.string(
                                        fromByteCount: monitor.metrics.totalBytesProcessed,
                                        countStyle: .file
                                    ))
                                    .bold()
                                }
                                
                                HStack {
                                    Text("Average Speed:")
                                    Spacer()
                                    Text(String(format: "%.1f files/s", monitor.metrics.averageFilesPerSecond))
                                        .bold()
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(minWidth: 250, maxWidth: 300)
                
                // Right panel - Graphs and bottlenecks
                VStack(spacing: 0) {
                    // Metric selector
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(MetricType.allCases, id: \.self) { metric in
                            Label(metric.rawValue, systemImage: metric.icon)
                                .tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Chart
                    if !monitor.metrics.snapshots.isEmpty {
                        PerformanceChart(
                            snapshots: monitor.metrics.snapshots,
                            metricType: selectedMetric
                        )
                        .padding()
                    } else {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Performance data will appear here during operations")
                        )
                    }
                    
                    Divider()
                    
                    // Bottlenecks
                    if !monitor.metrics.bottlenecks.isEmpty {
                        BottlenecksList(bottlenecks: monitor.metrics.bottlenecks)
                            .frame(height: 150)
                    }
                }
                .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let progress: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .bold()
            }
            
            Spacer()
            
            CircularProgressView(progress: progress, color: color)
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
    }
}

struct PerformanceChart: View {
    let snapshots: [PerformanceSnapshot]
    let metricType: PerformanceDashboardView.MetricType
    
    private var data: [(date: Date, value: Double)] {
        snapshots.map { snapshot in
            let value: Double
            switch metricType {
            case .cpu:
                value = snapshot.cpuUsage * 100
            case .memory:
                value = snapshot.memoryUsage / (1024 * 1024 * 1024) // Convert to GB
            case .filesPerSecond:
                value = snapshot.filesProcessedPerSecond
            case .diskIO:
                value = snapshot.diskUsage / (1024 * 1024) // Convert to MB
            }
            return (snapshot.timestamp, value)
        }
    }
    
    private var yAxisLabel: String {
        switch metricType {
        case .cpu: return "Percentage"
        case .memory: return "GB"
        case .filesPerSecond: return "Files/s"
        case .diskIO: return "MB"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(metricType.rawValue)
                .font(.headline)
            
            Chart(data, id: \.date) { item in
                LineMark(
                    x: .value("Time", item.date),
                    y: .value(yAxisLabel, item.value)
                )
                .foregroundStyle(metricType.color)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", item.date),
                    y: .value(yAxisLabel, item.value)
                )
                .foregroundStyle(metricType.color.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(formatAxisValue(doubleValue))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour().minute().second()))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }
    
    private func formatAxisValue(_ value: Double) -> String {
        switch metricType {
        case .cpu:
            return String(format: "%.0f%%", value)
        case .memory:
            return String(format: "%.1fGB", value)
        case .filesPerSecond:
            return String(format: "%.0f", value)
        case .diskIO:
            return String(format: "%.0fMB", value)
        }
    }
}

struct BottlenecksList: View {
    let bottlenecks: [Bottleneck]
    
    var recentBottlenecks: [Bottleneck] {
        Array(bottlenecks.suffix(10).reversed())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Detected Bottlenecks", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(recentBottlenecks.enumerated()), id: \.offset) { _, bottleneck in
                        BottleneckRow(bottleneck: bottleneck)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

struct BottleneckRow: View {
    let bottleneck: Bottleneck
    
    var icon: String {
        switch bottleneck.type {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .processingSpeed: return "speedometer"
        case .queueDepth: return "tray.full"
        }
    }
    
    var color: Color {
        switch bottleneck.severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bottleneck.description)
                    .font(.caption)
                Text(bottleneck.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    PerformanceDashboardView()
        .frame(width: 800, height: 600)
}