import SwiftUI
import SwiftData
import AppKit

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
    @State private var globalResolutionAction: ResolutionAction?
    @State private var showingWorkflowGuide = false
    @State private var dataActor: DataActor?
    
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
    
    var availableCameras: Set<String> {
        var cameras = Set<String>()
        for group in duplicateGroups {
            for file in group.files {
                if let camera = file.cameraModel {
                    cameras.insert(camera)
                }
            }
        }
        return cameras
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with toolbar
            VStack(spacing: 0) {
                HStack {
                    Text("Duplicate Management")
                        .font(.largeTitle)
                        .bold()
                    
                    Button(action: { showingWorkflowGuide = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Show workflow guide")
                    
                    Spacer()
                    
                    if selectedGroupsCount > 0 {
                        VStack(alignment: .trailing) {
                            Text("\(selectedGroupsCount) groups selected")
                                .font(.headline)
                            Text("\(formattedSpaceSaved) to recover")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                HStack {
                    Button("Select All") {
                        selectAll()
                    }
                    .disabled(duplicateGroups.isEmpty)
                    
                    Button("Select None") {
                        selectNone()
                    }
                    .disabled(selectedGroups.isEmpty)
                    
                    Menu("Smart Select") {
                        Button("Auto-select Best Quality") {
                            autoSelectBestQuality()
                        }
                        
                        Divider()
                        
                        Button("Select Groups with Thumbnails") {
                            selectGroupsWithThumbnails()
                        }
                        
                        Button("Select Groups without Metadata") {
                            selectGroupsWithoutMetadata()
                        }
                        
                        Button("Select Large Groups (5+ files)") {
                            selectLargeGroups()
                        }
                        
                        Divider()
                        
                        Menu("By File Size") {
                            Button("Small Files (< 1MB)") {
                                selectByFileSize(maxSize: 1_000_000)
                            }
                            Button("Medium Files (1-5MB)") {
                                selectByFileSize(minSize: 1_000_000, maxSize: 5_000_000)
                            }
                            Button("Large Files (> 5MB)") {
                                selectByFileSize(minSize: 5_000_000)
                            }
                        }
                        
                        if availableCameras.count > 0 {
                            Menu("By Camera") {
                                ForEach(Array(availableCameras).sorted(), id: \.self) { camera in
                                    Button(camera) {
                                        selectByCamera(camera)
                                    }
                                }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                    .disabled(duplicateGroups.isEmpty)
                    
                    if selectedGroupsCount > 0 {
                        Menu("Apply Resolution to All") {
                            Section("Keep Options") {
                                ForEach(ResolutionAction.allCases.filter { $0 != .keepAll && $0 != .deleteAll }, id: \.self) { action in
                                    Button(action.rawValue) {
                                        applyGlobalResolution(action)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Danger Zone") {
                                Button(action: {
                                    applyGlobalResolution(.deleteAll)
                                }) {
                                    Label("Delete All Files", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .menuStyle(.borderedButton)
                        .help("Apply the same resolution rule to all selected groups")
                    }
                    
                    Spacer()
                    
                    Button("Clean Up Selected") {
                        showingConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedGroups.isEmpty || isProcessing)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main content
            if duplicateGroups.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("No duplicates found")
                        .font(.title)
                        .bold()
                    Text("Your image collection is already optimized!")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 600), spacing: 20)], spacing: 20) {
                        ForEach(duplicateGroups) { group in
                            DuplicateGroupCard(
                                group: group,
                                isSelected: selectedGroups.contains(group.id),
                                isExpanded: expandedGroups.contains(group.id),
                                selectedFileID: selectedFilesToKeep[group.id],
                                onToggleSelection: { toggleGroupSelection(group) },
                                onToggleExpansion: { toggleGroupExpansion(group) },
                                onFileSelection: { fileID in
                                    // If fileID is a new UUID (invalid), it means we're clearing selection for delete all
                                    if group.files.contains(where: { $0.id == fileID }) {
                                        selectedFilesToKeep[group.id] = fileID
                                    } else {
                                        // Clear selection for delete all
                                        selectedFilesToKeep.removeValue(forKey: group.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            // Progress overlay
            if isProcessing {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 20) {
                            ProgressView(value: processingProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 400)
                            
                            Text(processingStatus)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(20)
                        .shadow(radius: 20)
                    )
            }
        }
        .alert("Confirm Cleanup", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clean Up", role: .destructive) {
                performCleanup()
            }
        } message: {
            let deleteCount = calculateFilesToDelete()
            let hasDeleteAll = duplicateGroups
                .filter { selectedGroups.contains($0.id) }
                .contains { selectedFilesToKeep[$0.id] == nil }
            
            if hasDeleteAll {
                Text("⚠️ WARNING: This will move \(deleteCount) files to the trash, recovering \(formattedSpaceSaved) of space. Some groups will have ALL files deleted. This action cannot be undone.")
            } else {
                Text("This will move \(deleteCount) files to the trash, recovering \(formattedSpaceSaved) of space. This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showingResults) {
            CleanupResultsView(results: deletionResults ?? DeletionResults())
        }
        .sheet(isPresented: $showingWorkflowGuide) {
            DuplicateWorkflowGuide(showingGuide: $showingWorkflowGuide)
        }
        .onAppear {
            let container = modelContext.container
            dataActor = DataActor(modelContainer: container)
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
                // If no file is selected to keep, all files will be deleted
                let keepCount = selectedFilesToKeep[group.id] != nil ? 1 : 0
                let deleteCount = keepCount == 0 ? group.files.count : group.files.count - 1
                return total + deleteCount
            }
    }
    
    private func performCleanup() {
        isProcessing = true
        processingProgress = 0.0
        processingStatus = "Preparing cleanup..."
        
        Task {
            guard let dataActor = dataActor else { return }
            
            var results = DeletionResults()
            let selectedGroupsList = duplicateGroups.filter { selectedGroups.contains($0.id) }
            let totalFiles = calculateFilesToDelete()
            var processedFiles = 0
            
            for group in selectedGroupsList {
                let fileToKeepID = selectedFilesToKeep[group.id]
                
                if fileToKeepID == nil {
                    // Delete all files in the group
                    await MainActor.run {
                        processingStatus = "Deleting all files in group..."
                    }
                    
                    for file in group.files {
                        do {
                            try await dataActor.deleteDuplicateFile(file.id)
                            results.deletedFiles += 1
                            results.spaceSaved += file.fileSize
                        } catch {
                            results.failedFiles += 1
                            results.errors.append("\(file.fileName): \(error.localizedDescription)")
                        }
                        
                        processedFiles += 1
                        await MainActor.run {
                            processingProgress = Double(processedFiles) / Double(totalFiles)
                        }
                    }
                    
                    // Delete the entire group
                    try? await dataActor.deleteDuplicateGroup(group.id)
                } else {
                    // Keep one file, delete others
                    var filesToRemove: [ScannedFile] = []
                    
                    for file in group.files where file.id != fileToKeepID {
                        await MainActor.run {
                            processingStatus = "Deleting \(file.fileName)..."
                        }
                        
                        do {
                            try await dataActor.deleteDuplicateFile(file.id)
                            results.deletedFiles += 1
                            results.spaceSaved += file.fileSize
                            filesToRemove.append(file)
                        } catch {
                            results.failedFiles += 1
                            results.errors.append("\(file.fileName): \(error.localizedDescription)")
                        }
                        
                        processedFiles += 1
                        await MainActor.run {
                            processingProgress = Double(processedFiles) / Double(totalFiles)
                        }
                    }
                    
                    // Update group
                    try? await dataActor.updateDuplicateGroup(
                        group.id,
                        removeFileIDs: filesToRemove.map { $0.id },
                        markResolved: true
                    )
                }
            }
            
            await MainActor.run {
                isProcessing = false
                deletionResults = results
                showingResults = true
                selectedGroups.removeAll()
                selectedFilesToKeep.removeAll()
            }
        }
    }
    
    private func applyGlobalResolution(_ action: ResolutionAction) {
        globalResolutionAction = action
        
        for groupID in selectedGroups {
            guard let group = duplicateGroups.first(where: { $0.id == groupID }) else { continue }
            
            group.resolutionAction = action
            
            switch action {
            case .keepOldest:
                if let oldestFile = group.oldestFile {
                    selectedFilesToKeep[groupID] = oldestFile.id
                }
            case .keepNewest:
                if let newestFile = group.newestFile {
                    selectedFilesToKeep[groupID] = newestFile.id
                }
            case .keepLargest:
                if let largestFile = group.largestFile {
                    selectedFilesToKeep[groupID] = largestFile.id
                }
            case .keepBestQuality:
                if let bestFile = group.bestQualityFile {
                    selectedFilesToKeep[groupID] = bestFile.id
                }
            case .keepSelected:
                // Keep current selection or default to first file
                if selectedFilesToKeep[groupID] == nil {
                    selectedFilesToKeep[groupID] = group.files.first?.id
                }
            case .keepAll:
                // Should not reach here as we filter this out in the menu
                break
            case .deleteAll:
                // Mark all files for deletion (no file to keep)
                selectedFilesToKeep.removeValue(forKey: groupID)
            }
        }
    }
    
    // MARK: - Smart Selection Methods
    
    private func autoSelectBestQuality() {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups {
            selectedGroups.insert(group.id)
            
            // Automatically select the best quality file to keep
            if let bestFile = group.bestQualityFile {
                selectedFilesToKeep[group.id] = bestFile.id
                group.resolutionAction = .keepSelected
            } else {
                // Fallback to oldest if no clear best
                selectedFilesToKeep[group.id] = group.oldestFile?.id ?? group.files.first?.id
                group.resolutionAction = .keepOldest
            }
        }
    }
    
    private func selectGroupsWithThumbnails() {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups where group.hasLowQualityFiles {
            selectedGroups.insert(group.id)
            
            // Auto-select best quality file (usually not the thumbnail)
            if let bestFile = group.bestQualityFile {
                selectedFilesToKeep[group.id] = bestFile.id
            }
        }
    }
    
    private func selectGroupsWithoutMetadata() {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups {
            let hasNoMetadata = group.files.allSatisfy { !$0.hasMetadata }
            if hasNoMetadata {
                selectedGroups.insert(group.id)
                // Default to keeping the largest file when no metadata
                selectedFilesToKeep[group.id] = group.largestFile?.id ?? group.files.first?.id
            }
        }
    }
    
    private func selectLargeGroups() {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups where group.files.count >= 5 {
            selectedGroups.insert(group.id)
            
            // For large groups, prefer best quality
            if let bestFile = group.bestQualityFile {
                selectedFilesToKeep[group.id] = bestFile.id
            }
        }
    }
    
    private func selectByFileSize(minSize: Int64? = nil, maxSize: Int64? = nil) {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups {
            let meetsSize = group.files.allSatisfy { file in
                if let min = minSize, file.fileSize < min { return false }
                if let max = maxSize, file.fileSize > max { return false }
                return true
            }
            
            if meetsSize {
                selectedGroups.insert(group.id)
                
                // Auto-select best quality within size range
                if let bestFile = group.bestQualityFile {
                    selectedFilesToKeep[group.id] = bestFile.id
                }
            }
        }
    }
    
    private func selectByCamera(_ cameraModel: String) {
        selectedGroups.removeAll()
        selectedFilesToKeep.removeAll()
        
        for group in duplicateGroups {
            let hasCamera = group.files.contains { $0.cameraModel == cameraModel }
            if hasCamera {
                selectedGroups.insert(group.id)
                
                // Prefer keeping files from the specified camera
                if let cameraFile = group.files.first(where: { $0.cameraModel == cameraModel }) {
                    selectedFilesToKeep[group.id] = cameraFile.id
                } else {
                    // Fallback to best quality
                    if let bestFile = group.bestQualityFile {
                        selectedFilesToKeep[group.id] = bestFile.id
                    }
                }
            }
        }
    }
}

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let isSelected: Bool
    let isExpanded: Bool
    let selectedFileID: UUID?
    let onToggleSelection: () -> Void
    let onToggleExpansion: () -> Void
    let onFileSelection: (UUID) -> Void
    
    @State private var thumbnails: [UUID: NSImage] = [:]
    @State private var showingComparison = false
    @State private var showingMetadataMerge = false
    @State private var mergeRecommendation: MetadataMerger.MergeRecommendation?
    
    private let metadataMerger = MetadataMerger()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(group.files.count) \(group.sha256Hash.hasPrefix("visual_") ? "visually similar" : "duplicate") files")
                            .font(.title3)
                            .bold()
                        if group.sha256Hash.hasPrefix("visual_") {
                            HStack(spacing: 4) {
                                Label("Visual match", systemImage: "eye.fill")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                
                                // Show if any files have rotation suggestions
                                if group.files.contains(where: { $0.suggestedRotation != nil }) {
                                    Text("(rotation detected)")
                                        .font(.caption2)
                                        .foregroundColor(.purple.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                    Text("Size: \(group.files.first?.formattedFileSize ?? "Unknown") each")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Total savings: \(group.formattedSpaceSaved)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if isSelected && !group.isResolved {
                        Menu("Resolution") {
                            Section("Keep Options") {
                                ForEach(ResolutionAction.allCases.filter { $0 != .deleteAll }, id: \.self) { action in
                                    Button(action.rawValue) {
                                        group.resolutionAction = action
                                        if action == .keepOldest {
                                            onFileSelection(group.oldestFile?.id ?? group.files.first!.id)
                                        } else if action == .keepNewest {
                                            onFileSelection(group.newestFile?.id ?? group.files.first!.id)
                                        } else if action == .keepLargest {
                                            onFileSelection(group.largestFile?.id ?? group.files.first!.id)
                                        } else if action == .keepBestQuality {
                                            onFileSelection(group.bestQualityFile?.id ?? group.files.first!.id)
                                        } else if action == .keepAll {
                                            // Deselect group if keeping all
                                            onToggleSelection()
                                        }
                                        // keepSelected is handled by manual selection
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Danger Zone") {
                                Button(action: {
                                    group.resolutionAction = .deleteAll
                                    // Clear selection when deleting all
                                    onFileSelection(UUID()) // Pass invalid UUID to clear selection
                                }) {
                                    Label("Delete All Files", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .menuStyle(.borderedButton)
                    }
                    
                    Button(action: { showingComparison = true }) {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                    }
                    .buttonStyle(.bordered)
                    
                    if group.files.count == 2 && isSelected {
                        Button(action: {
                            mergeRecommendation = metadataMerger.recommendMerge(for: group)
                            showingMetadataMerge = true
                        }) {
                            Label("Merge Metadata", systemImage: "arrow.triangle.merge")
                        }
                        .buttonStyle(.bordered)
                        .help("View metadata merge suggestions")
                    }
                    
                    Button(action: onToggleExpansion) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            
            // Expanded content with thumbnail grid
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    if isSelected {
                        HStack {
                            if group.resolutionAction == .deleteAll {
                                Text("All files will be deleted")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            } else {
                                Text("Select file to keep:")
                                    .font(.headline)
                            }
                            
                            if let action = group.resolutionAction {
                                Spacer()
                                Label(action.rawValue, systemImage: resolutionIcon(for: action))
                                    .font(.subheadline)
                                    .foregroundColor(action == .deleteAll ? .red : .accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(action == .deleteAll ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Select this group to choose which file to keep")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(group.files) { file in
                            FileSelectionCard(
                                file: file,
                                isSelected: isSelected && selectedFileID == file.id,
                                isMarkedForDeletion: group.resolutionAction == .deleteAll,
                                thumbnail: thumbnails[file.id]
                            ) {
                                if group.resolutionAction != .deleteAll {
                                    if isSelected {
                                        onFileSelection(file.id)
                                    } else {
                                        // First select the group, then the file
                                        onToggleSelection()
                                        onFileSelection(file.id)
                                    }
                                }
                            }
                            .disabled(!isSelected || group.resolutionAction == .deleteAll)
                            .opacity(isSelected && group.resolutionAction != .deleteAll ? 1.0 : 0.7)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .shadow(radius: isSelected ? 8 : 4)
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
        .sheet(isPresented: $showingMetadataMerge) {
            if let recommendation = mergeRecommendation {
                MetadataMergeView(recommendation: recommendation, group: group)
            }
        }
    }
    
    private func loadThumbnails() {
        let targetSize = CGSize(width: 150, height: 150)
        
        for file in group.files {
            guard thumbnails[file.id] == nil else { continue }
            
            DispatchQueue.global(qos: .userInitiated).async {
                if let image = NSImage(contentsOf: file.url) {
                    let thumbnail = self.createThumbnail(from: image, targetSize: targetSize)
                    
                    DispatchQueue.main.async {
                        self.thumbnails[file.id] = thumbnail
                    }
                }
            }
        }
    }
    
    private func createThumbnail(from image: NSImage, targetSize: CGSize) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return image }
        
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
        )
        
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        
        return thumbnail
    }
    
    private func resolutionIcon(for action: ResolutionAction) -> String {
        switch action {
        case .keepOldest:
            return "clock.badge.checkmark"
        case .keepNewest:
            return "clock.arrow.circlepath"
        case .keepLargest:
            return "arrow.up.circle"
        case .keepBestQuality:
            return "star.fill"
        case .keepSelected:
            return "hand.point.up"
        case .keepAll:
            return "checkmark.circle"
        case .deleteAll:
            return "trash"
        }
    }
}

struct FileSelectionCard: View {
    let file: ScannedFile
    let isSelected: Bool
    var isMarkedForDeletion: Bool = false
    let thumbnail: NSImage?
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                        .overlay(
                            // Rotation indicator
                            Group {
                                if let rotation = file.suggestedRotation {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            RotationIndicator(rotation: rotation)
                                                .padding(4)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        )
                } else {
                    ProgressView()
                }
                
                if isMarkedForDeletion {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 4)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "trash.circle.fill")
                                .font(.title)
                                .foregroundColor(.red)
                                .background(Circle().fill(.white))
                                .padding(8)
                        }
                        Spacer()
                    }
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 4)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.green)
                                .background(Circle().fill(.white))
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                
                HStack {
                    Text(file.formattedFileSize)
                        .font(.caption)
                    Spacer()
                    if let date = file.originalCreationDate ?? file.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                
                // Metadata quality indicator
                HStack(spacing: 4) {
                    MetadataQualityIndicator(score: file.metadataQualityScore)
                    
                    if file.isThumbnail || file.isPotentialThumbnail {
                        Label("Thumbnail", systemImage: "photo.badge.minus")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                if let camera = file.cameraModel {
                    Label(camera, systemImage: "camera")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            isMarkedForDeletion ? Color.red.opacity(0.1) :
            isSelected ? Color.green.opacity(0.1) :
            Color(NSColor.controlBackgroundColor)
        )
        .cornerRadius(12)
        .shadow(radius: isSelected || isMarkedForDeletion ? 4 : 2)
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