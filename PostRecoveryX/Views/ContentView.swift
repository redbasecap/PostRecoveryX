import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = MainViewModel()
    @Query(sort: \ScanSession.startDate, order: .reverse) private var sessions: [ScanSession]
    @Query private var duplicateGroups: [DuplicateGroup]
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
            
            DuplicateManagementView()
                .tabItem {
                    Label("Duplicates", systemImage: "square.on.square")
                }
                .tag("duplicates")
            
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
            
            HistoryView(sessions: sessions)
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
                    viewModel.continueSession(session)
                }
            }
            Button("Start Fresh", role: .destructive) {
                if let session = lastIncompleteSession {
                    clearIncompleteSession(session)
                }
            }
        } message: {
            if let session = lastIncompleteSession {
                Text("Found an incomplete scan from \(session.scanPath).\nWould you like to continue where you left off?")
            }
        }
    }
    
    private func checkForPreviousSession() {
        guard !hasCheckedForPreviousSession else { return }
        hasCheckedForPreviousSession = true
        
        if lastIncompleteSession != nil && !duplicateGroups.isEmpty {
            showingSessionPrompt = true
        }
    }
    
    private func clearIncompleteSession(_ session: ScanSession) {
        // Mark session as cancelled
        session.status = .cancelled
        session.endDate = Date()
        
        // Clear associated duplicate groups
        for group in duplicateGroups {
            modelContext.delete(group)
        }
        
        // Clear scanned files from this session
        if let files = try? modelContext.fetch(FetchDescriptor<ScannedFile>()) {
            for file in files {
                if file.duplicateGroup != nil {
                    modelContext.delete(file)
                }
            }
        }
        
        try? modelContext.save()
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
            
            HStack {
                Toggle("Include video files", isOn: $viewModel.includeVideos)
                Toggle("Visual similarity matching", isOn: $viewModel.enableVisualMatching)
                    .help("Detects rotated or visually similar images")
            }
            .padding(.horizontal, 40)
            
            if viewModel.isScanning {
                VStack(spacing: 10) {
                    ProgressView(value: viewModel.scanProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                    
                    Text(viewModel.scanStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Cancel") {
                        Task {
                            await viewModel.cancelScan()
                        }
                    }
                    .buttonStyle(.bordered)
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
    }
}


struct HistoryView: View {
    let sessions: [ScanSession]
    
    var body: some View {
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
            OrganizationTask.self
        ], inMemory: true)
}