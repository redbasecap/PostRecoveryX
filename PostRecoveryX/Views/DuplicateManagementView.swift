import SwiftUI
import SwiftData
import QuickLookThumbnailing

struct DuplicateManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<DuplicateGroup> { group in
        group.files.count > 1
    }) private var duplicateGroups: [DuplicateGroup]
    
    @State private var selectedGroups = Set<UUID>()
    @State private var expandedGroups = Set<UUID>()
    @State private var selectedFilesToKeep = [UUID: UUID]() // [groupID: fileID]
    @State private var showingConfirmation = false
    @State private var isProcessing = false
    @State private var processingProgress = 0.0
    @State private var processingStatus = ""
    @State private var showingResults = false
    @State private var deletionResults: DeletionResults?
    
    var selectedGroupsCount: Int {
        selectedGroups.count
    }
    
    var potentialSpaceSaved: Int64 {
        duplicateGroups
            .filter { selectedGroups.contains($0.id) }
            .reduce(0) { total, group in
                let keepCount = selectedFilesToKeep[group.id] != nil ? 1 : 0
                let deleteCount = max(0, group.files.count - keepCount)
                return total + (group.fileSize * Int64(deleteCount))
            }
    }
    
    var formattedSpaceSaved: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: potentialSpaceSaved)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button("Select All") {
                        selectAll()
                    }
                    .disabled(duplicateGroups.isEmpty)
                    
                    Button("Select None") {
                        selectNone()
                    }
                    .disabled(selectedGroups.isEmpty)
                    
                    Spacer()
                    
                    if selectedGroupsCount > 0 {
                        Text("\(selectedGroupsCount) groups selected • \(formattedSpaceSaved) to recover")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clean Up Selected") {
                        showingConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedGroups.isEmpty || isProcessing)
                }
                .padding()
                
                Divider()
                
                // Main content
                if duplicateGroups.isEmpty {
                    VStack {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("No duplicates found")
                            .font(.title2)
                            .padding(.top)
                        Text("Your image collection is already optimized!")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(duplicateGroups) { group in
                                DuplicateGroupRow(
                                    group: group,
                                    isSelected: selectedGroups.contains(group.id),
                                    isExpanded: expandedGroups.contains(group.id),
                                    selectedFileID: selectedFilesToKeep[group.id],
                                    onToggleSelection: { toggleGroupSelection(group) },
                                    onToggleExpansion: { toggleGroupExpansion(group) },
                                    onFileSelection: { fileID in
                                        selectedFilesToKeep[group.id] = fileID
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                // Progress overlay
                if isProcessing {
                    VStack(spacing: 20) {
                        ProgressView(value: processingProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 300)
                        
                        Text(processingStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
            .navigationTitle("Duplicate Management")
            .alert("Confirm Cleanup", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clean Up", role: .destructive) {
                    performCleanup()
                }
            } message: {
                Text("This will move \(calculateFilesToDelete()) files to the trash, recovering \(formattedSpaceSaved) of space. This action cannot be undone.")
            }
            .sheet(isPresented: $showingResults) {
                CleanupResultsView(results: deletionResults ?? DeletionResults())
            }
        }
    }
    
    private func selectAll() {
        for group in duplicateGroups {
            selectedGroups.insert(group.id)
            // Auto-select the oldest file to keep by default
            if selectedFilesToKeep[group.id] == nil {
                selectedFilesToKeep[group.id] = group.oldestFile?.id
            }
        }
    }
    
    private func selectNone() {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
    }
    
    private func toggleGroupSelection(_ group: DuplicateGroup) {
        if selectedGroups.contains(group.id) {
            selectedGroups.remove(group.id)
            selectedFilesToKeep.removeValue(forKey: group.id)
        } else {
            selectedGroups.insert(group.id)
            // Auto-select the oldest file to keep by default
            if selectedFilesToKeep[group.id] == nil {
                selectedFilesToKeep[group.id] = group.oldestFile?.id
            }
        }
    }
    
    private func toggleGroupExpansion(_ group: DuplicateGroup) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
        }
    }
    
    private func calculateFilesToDelete() -> Int {
        return duplicateGroups
            .filter { selectedGroups.contains($0.id) }
            .reduce(0) { total, group in
                let keepCount = selectedFilesToKeep[group.id] != nil ? 1 : 0
                return total + max(0, group.files.count - keepCount)
            }
    }
    
    private func performCleanup() {
        isProcessing = true
        processingProgress = 0.0
        processingStatus = "Preparing cleanup..."
        
        Task {
            var results = DeletionResults()
            let selectedGroupsList = duplicateGroups.filter { selectedGroups.contains($0.id) }
            let totalFiles = calculateFilesToDelete()
            var processedFiles = 0
            
            for group in selectedGroupsList {
                guard let fileToKeepID = selectedFilesToKeep[group.id] else { continue }
                
                for file in group.files where file.id != fileToKeepID {
                    processingStatus = "Deleting \(file.fileName)..."
                    
                    do {
                        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                        results.deletedFiles += 1
                        results.spaceSaved += file.fileSize
                        
                        // Remove from model
                        modelContext.delete(file)
                    } catch {
                        results.failedFiles += 1
                        results.errors.append("\(file.fileName): \(error.localizedDescription)")
                    }
                    
                    processedFiles += 1
                    processingProgress = Double(processedFiles) / Double(totalFiles)
                }
                
                // Update group
                group.files.removeAll { $0.id != fileToKeepID }
                group.fileCount = 1
                group.isResolved = true
                
                // Remove group if only one file remains
                if group.files.count <= 1 {
                    modelContext.delete(group)
                }
            }
            
            try? modelContext.save()
            
            await MainActor.run {
                isProcessing = false
                deletionResults = results
                showingResults = true
                selectedGroups.removeAll()
                selectedFilesToKeep.removeAll()
            }
        }
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isSelected: Bool
    let isExpanded: Bool
    let selectedFileID: UUID?
    let onToggleSelection: () -> Void
    let onToggleExpansion: () -> Void
    let onFileSelection: (UUID) -> Void
    
    @State private var thumbnails: [UUID: NSImage] = [:]
    @State private var showingComparison = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(group.files.count) duplicate files")
                            .font(.headline)
                        if group.isPerceptualMatch {
                            Label("Visual match", systemImage: "rotate.right")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    Text("Size: \(group.files.first?.formattedFileSize ?? "Unknown") each • Total savings: \(group.formattedSpaceSaved)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingComparison = true }) {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button(action: onToggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Expanded content
            if isExpanded && isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select file to keep:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(group.files) { file in
                                FileSelectionCard(
                                    file: file,
                                    isSelected: selectedFileID == file.id,
                                    thumbnail: thumbnails[file.id]
                                ) {
                                    onFileSelection(file.id)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onAppear {
            if isExpanded {
                loadThumbnails()
            }
        }
        .onChange(of: isExpanded) { oldValue, newValue in
            if newValue {
                loadThumbnails()
            }
        }
        .sheet(isPresented: $showingComparison) {
            DuplicateComparisonView(group: group)
        }
    }
    
    private func loadThumbnails() {
        let size = CGSize(width: 120, height: 120)
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        
        for file in group.files {
            guard thumbnails[file.id] == nil else { continue }
            
            let request = QLThumbnailGenerator.Request(
                fileAt: file.url,
                size: size,
                scale: scale,
                representationTypes: .all
            )
            
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, type, error in
                if let thumbnail = thumbnail {
                    DispatchQueue.main.async {
                        self.thumbnails[file.id] = thumbnail.nsImage
                    }
                }
            }
        }
    }
}

struct FileSelectionCard: View {
    let file: ScannedFile
    let isSelected: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(6)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green, lineWidth: 3)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .background(Circle().fill(.white))
                        .position(x: 105, y: 15)
                }
            }
            
            Text(file.fileName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 120)
            
            Text(file.originalCreationDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onTapGesture(perform: onTap)
    }
}

struct DeletionResults {
    var deletedFiles: Int = 0
    var failedFiles: Int = 0
    var spaceSaved: Int64 = 0
    var errors: [String] = []
}

struct CleanupResultsView: View {
    let results: DeletionResults
    @Environment(\.dismiss) private var dismiss
    
    var formattedSpaceSaved: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: results.spaceSaved)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: results.failedFiles == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(results.failedFiles == 0 ? .green : .orange)
            
            Text("Cleanup Complete")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.green)
                    Text("\(results.deletedFiles) files moved to trash")
                }
                
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(.blue)
                    Text("\(formattedSpaceSaved) of space recovered")
                }
                
                if results.failedFiles > 0 {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("\(results.failedFiles) files failed to delete")
                    }
                }
            }
            .font(.body)
            
            if !results.errors.isEmpty {
                GroupBox("Errors") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(results.errors, id: \.self) { error in
                                Text("• \(error)")
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(minWidth: 400)
    }
}