import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = MainViewModel()
    @Query(sort: \ScanSession.startDate, order: .reverse) private var sessions: [ScanSession]
    @State private var duplicateGroupCount: Int = 0
    @State private var selectedTab = "scan"
    @State private var showingSessionPrompt = false
    @State private var hasCheckedForPreviousSession = false
    
    var lastIncompleteSession: ScanSession? {
        sessions.first { session in
            session.status == .scanning || session.status == .processing
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView(viewModel: viewModel)
                .tabItem {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .tag("scan")
            
            OptimizedDuplicateManagementView()
                .tabItem {
                    Label("Duplicates", systemImage: "square.on.square")
                }
                .tag("duplicates")
            
            SimilarScenesView()
                .tabItem {
                    Label("Similar Scenes", systemImage: "rectangle.stack")
                }
                .tag("scenes")
            
            ThumbnailManagementView()
                .tabItem {
                    Label("Thumbnails", systemImage: "photo.stack")
                }
                .tag("thumbnails")
            
            OrganizationView()
                .tabItem {
                    Label("Organize", systemImage: "folder.badge.gearshape")
                }
                .tag("organize")
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag("history")
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            checkForPreviousSession()
        }
        .alert("Continue Previous Session?", isPresented: $showingSessionPrompt) {
            Button("Continue") {
                if let session = lastIncompleteSession {
                    Task {
                        await viewModel.continueSession(session)
                        selectedTab = "scan"
                    }
                }
            }
            Button("Start Fresh", role: .cancel) {
                if let session = lastIncompleteSession {
                    Task {
                        await clearIncompleteSession(session)
                    }
                }
            }
        } message: {
            if let session = lastIncompleteSession {
                let scannedCount = session.totalFilesProcessed
                let status = session.status == .scanning ? "scanning" : "processing"
                Text("Found an incomplete \(status) session from:\n\(session.scanPath)\n\nProgress: \(scannedCount) files scanned\nStarted: \(session.startDate.formatted())\n\nWould you like to continue where you left off?")
            }
        }
    }
    
    private func checkForPreviousSession() {
        guard !hasCheckedForPreviousSession else { return }
        hasCheckedForPreviousSession = true
        
        if lastIncompleteSession != nil {
            showingSessionPrompt = true
        }
    }
    
    private func clearIncompleteSession(_ session: ScanSession) async {
        let container = modelContext.container
        let dataActor = DataActor(modelContainer: container)
        try? await dataActor.clearIncompleteSession(session.id)
    }
}

struct ScanView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("PostRecoveryX")
                .font(.largeTitle)
                .bold()
            
            Text("Organize your recovered images and remove duplicates")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical)
            
            HStack {
                TextField("Select a folder to scan...", text: $viewModel.scanPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                
                Button("Browse...") {
                    viewModel.selectFolder()
                }
                .disabled(viewModel.isScanning)
            }
            .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Scan all file types", isOn: $viewModel.scanAllFileTypes)
                    .help("Scan all files and select types to process after scanning")
                
                Toggle("Visual similarity matching (experimental)", isOn: $viewModel.enableVisualMatching)
                    .help("Detects rotated or visually similar images - may have false positives")
            }
            .padding(.horizontal, 40)
            
            if viewModel.isScanning {
                VStack(spacing: 16) {
                    // Phase indicator with percentage
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: phaseIcon(for: viewModel.currentPhase))
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            
                            Text(viewModel.currentPhase.rawValue)
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        // Percentage
                        Text("\(viewModel.progressPercentage)%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 40)
                    
                    // Progress bar
                    ProgressView(value: viewModel.scanProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                    
                    // Time estimate
                    if viewModel.estimatedTimeRemaining > 0 {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("Estimated time remaining: \(formatTimeRemaining(viewModel.estimatedTimeRemaining))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Status text
                    VStack(spacing: 4) {
                        Text(viewModel.scanStatus)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if !viewModel.currentFile.isEmpty {
                            Text(viewModel.currentFile)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 400)
                        }
                        
                        if viewModel.totalFiles > 0 && viewModel.filesProcessed > 0 {
                            Text("\(viewModel.filesProcessed) of \(viewModel.totalFiles) files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button("Cancel") {
                        Task {
                            await viewModel.cancelScan()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    // Performance Dashboard - Always shown during scanning
                    GroupBox("Performance Monitor") {
                        PerformanceDashboardView()
                            .frame(height: 350)
                    }
                    .padding(.horizontal, 40)
                }
            } else {
                Button("Start Scan") {
                    Task {
                        await viewModel.startScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.scanPath.isEmpty)
            }
            
            if let session = viewModel.currentSession {
                GroupBox("Current Scan") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Files Found:")
                            Spacer()
                            Text("\(session.totalFilesFound)")
                        }
                        HStack {
                            Text("Files Processed:")
                            Spacer()
                            Text("\(session.totalFilesProcessed)")
                        }
                        HStack {
                            Text("Duplicates Found:")
                            Spacer()
                            Text("\(session.duplicatesFound)")
                        }
                        if session.totalSpaceSaved > 0 {
                            HStack {
                                Text("Potential Space Saved:")
                                Spacer()
                                Text(session.formattedSpaceSaved)
                            }
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $viewModel.showFileTypeSelection) {
            FileTypeSelectionView(
                discoveredFileTypeCounts: viewModel.discoveredFileTypeCounts,
                onComplete: {
                    await viewModel.processSelectedFileTypes()
                }
            )
        }
    }
    
    private func phaseIcon(for phase: ScanPhase) -> String {
        switch phase {
        case .idle:
            return "circle"
        case .discovering:
            return "magnifyingglass"
        case .creatingRecords:
            return "doc.badge.plus"
        case .extractingMetadata:
            return "info.circle"
        case .checkingDuplicates:
            return "square.on.square"
        case .detectingScenes:
            return "rectangle.stack"
        case .complete:
            return "checkmark.circle"
        }
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "calculating..."
    }
}


struct HistoryView: View {
    @Query(sort: \ScanSession.startDate, order: .reverse) private var sessions: [ScanSession]
    
    var body: some View {
        NavigationStack {
            if sessions.isEmpty {
                ContentUnavailableView("No Scan History", 
                                     systemImage: "clock",
                                     description: Text("Your scan history will appear here"))
            } else {
                List(sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.scanPath)
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: session.status)
                        }
                        
                        HStack {
                            Text("Started: \(session.startDate.formatted())")
                            if let duration = session.formattedDuration {
                                Text("• Duration: \(duration)")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Files: \(session.totalFilesFound)")
                            Text("• Duplicates: \(session.duplicatesFound)")
                            if session.totalSpaceSaved > 0 {
                                Text("• Saved: \(session.formattedSpaceSaved)")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle("Scan History")
            }
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    var backgroundColor: Color {
        switch status {
        case .scanning, .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            ScanSession.self,
            ScannedFile.self,
            DuplicateGroup.self,
            OrganizationTask.self,
            SimilarSceneGroup.self
        ], inMemory: true)
}