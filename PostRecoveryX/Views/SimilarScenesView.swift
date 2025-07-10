import SwiftUI
import SwiftData

struct SimilarScenesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SimilarSceneGroup.createdDate, order: .reverse) private var sceneGroups: [SimilarSceneGroup]
    
    @State private var selectedGroup: SimilarSceneGroup?
    @State private var showingGroupDetail = false
    @State private var filterType: SceneGroupType?
    @State private var sortOrder = SortOrder.date
    
    enum SortOrder: String, CaseIterable {
        case date = "Date"
        case size = "Size"
        case count = "Count"
        case type = "Type"
    }
    
    var filteredGroups: [SimilarSceneGroup] {
        let filtered = filterType == nil ? sceneGroups : sceneGroups.filter { $0.groupType == filterType }
        
        switch sortOrder {
        case .date:
            return filtered.sorted { $0.createdDate > $1.createdDate }
        case .size:
            return filtered.sorted { $0.totalSize > $1.totalSize }
        case .count:
            return filtered.sorted { $0.fileCount > $1.fileCount }
        case .type:
            return filtered.sorted { $0.groupType.rawValue < $1.groupType.rawValue }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Similar Scenes")
                        .font(.title2)
                        .bold()
                    Text("\(filteredGroups.count) scene groups found")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Filter by type
                Picker("Filter", selection: $filterType) {
                    Text("All").tag(nil as SceneGroupType?)
                    ForEach([SceneGroupType.burst, .sequence, .event], id: \.self) { type in
                        Text(type.rawValue).tag(type as SceneGroupType?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                // Sort options
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding()
            
            Divider()
            
            // Scene groups list
            if filteredGroups.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No similar scenes detected")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Run a scan to detect burst shots, sequences, and events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredGroups) { group in
                            SceneGroupCard(group: group) {
                                selectedGroup = group
                                showingGroupDetail = true
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(item: $selectedGroup) { group in
            SceneGroupDetailView(group: group)
        }
    }
}

struct SceneGroupCard: View {
    let group: SimilarSceneGroup
    let onTap: () -> Void
    
    @State private var thumbnails: [NSImage?] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Type badge
                Label(group.groupType.rawValue, systemImage: iconForType(group.groupType))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorForType(group.groupType).opacity(0.2))
                    .foregroundColor(colorForType(group.groupType))
                    .cornerRadius(6)
                
                Spacer()
                
                // Stats
                HStack(spacing: 16) {
                    Label("\(group.fileCount) photos", systemImage: "photo.stack")
                    Label(group.formattedTotalSize, systemImage: "scalemass")
                    if let dateRange = group.dateRange {
                        Label(dateRange, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // Preview thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<min(6, thumbnails.count), id: \.self) { index in
                        if let image = thumbnails[index] {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    // Mark best photo
                                    group.files[index].id == group.bestFileId ?
                                    VStack {
                                        HStack {
                                            Image(systemName: "star.fill")
                                                .font(.caption)
                                                .foregroundColor(.yellow)
                                                .padding(4)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(4)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(4)
                                    : nil
                                )
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .cornerRadius(8)
                                .overlay {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }
                        }
                    }
                    
                    if group.fileCount > 6 {
                        Text("+\(group.fileCount - 6)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 80, height: 100)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                if let location = group.locationInfo {
                    Label(location, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Time span: \(group.formattedTimeRange)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if group.potentialSpaceSaved > 0 {
                        Text("Can save: \(ByteCountFormatter.string(fromByteCount: group.potentialSpaceSaved, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnails()
        }
    }
    
    private func loadThumbnails() {
        thumbnails = Array(repeating: nil, count: min(6, group.files.count))
        
        for (index, file) in group.files.prefix(6).enumerated() {
            Task {
                if let image = NSImage(contentsOf: file.url) {
                    await MainActor.run {
                        if index < thumbnails.count {
                            thumbnails[index] = image
                        }
                    }
                }
            }
        }
    }
    
    private func iconForType(_ type: SceneGroupType) -> String {
        switch type {
        case .burst:
            return "camera.on.rectangle"
        case .sequence:
            return "rectangle.stack"
        case .event:
            return "calendar"
        case .location:
            return "location"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    private func colorForType(_ type: SceneGroupType) -> Color {
        switch type {
        case .burst:
            return .orange
        case .sequence:
            return .blue
        case .event:
            return .purple
        case .location:
            return .green
        case .unknown:
            return .gray
        }
    }
}

struct SceneGroupDetailView: View {
    let group: SimilarSceneGroup
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFiles: Set<ScannedFile> = []
    @State private var showingDeleteConfirmation = false
    @State private var viewMode: ViewMode = .grid
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("\(group.groupType.rawValue) Group")
                        .font(.title2)
                        .bold()
                    Text("\(group.fileCount) photos • \(group.formattedTotalSize)")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Toolbar
            HStack {
                Button("Select All") {
                    selectedFiles = Set(group.files)
                }
                
                Button("Select All Except Best") {
                    selectedFiles = Set(group.files.filter { $0.id != group.bestFileId })
                }
                
                Spacer()
                
                Text("\(selectedFiles.count) selected")
                    .foregroundColor(.secondary)
                
                Button("Delete Selected") {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedFiles.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            ScrollView {
                if viewMode == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(group.files) { file in
                            SceneFileGridItem(
                                file: file,
                                isBest: file.id == group.bestFileId,
                                isSelected: selectedFiles.contains(file)
                            ) {
                                if selectedFiles.contains(file) {
                                    selectedFiles.remove(file)
                                } else {
                                    selectedFiles.insert(file)
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(group.files) { file in
                            SceneFileListItem(
                                file: file,
                                isBest: file.id == group.bestFileId,
                                isSelected: selectedFiles.contains(file)
                            ) {
                                if selectedFiles.contains(file) {
                                    selectedFiles.remove(file)
                                } else {
                                    selectedFiles.insert(file)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 900, height: 700)
        .alert("Delete Files", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedFiles()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedFiles.count) file(s)? This action cannot be undone.")
        }
    }
    
    private func deleteSelectedFiles() {
        // Implementation for deleting files
        // Similar to thumbnail deletion
    }
}

struct SceneFileGridItem: View {
    let file: ScannedFile
    let isBest: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var thumbnail: NSImage?
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                    }
                }
                .frame(width: 150, height: 150)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    isBest ?
                    VStack {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(4)
                    : nil
                )
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(.white))
                        .padding(8)
                }
            }
            
            Text(file.fileName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 150)
            
            Text(file.formattedFileSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            if let image = NSImage(contentsOf: file.url) {
                await MainActor.run {
                    self.thumbnail = image
                }
            }
        }
    }
}

struct SceneFileListItem: View {
    let file: ScannedFile
    let isBest: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            
            if isBest {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading) {
                Text(file.fileName)
                    .lineLimit(1)
                
                HStack {
                    Text(file.formattedFileSize)
                    if let date = file.originalCreationDate ?? file.creationDate {
                        Text("• \(date.formatted())")
                    }
                    if let dims = file.width, let height = file.height {
                        Text("• \(dims)×\(height)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    SimilarScenesView()
        .modelContainer(for: [
            SimilarSceneGroup.self,
            ScannedFile.self
        ], inMemory: true)
}