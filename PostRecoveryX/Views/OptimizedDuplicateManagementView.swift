import SwiftUI
import SwiftData

struct OptimizedDuplicateManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var selectedGroup: DuplicateGroup?
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var totalGroups = 0
    @State private var sortOrder = SortOrder.spaceSaved
    @State private var filterMinSize: Int64 = 0
    
    private let pageSize = 50
    
    enum SortOrder: String, CaseIterable {
        case spaceSaved = "Space Saved"
        case fileCount = "File Count"
        case fileSize = "File Size"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duplicate Management")
                        .font(.title2)
                        .bold()
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        // Pagination info
                        HStack {
                            Button(action: previousPage) {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(currentPage == 0)
                            
                            Text("Page \(currentPage + 1) of \(totalPages)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(action: nextPage) {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(currentPage >= totalPages - 1)
                        }
                    }
                }
                
                // Stats
                if !duplicateGroups.isEmpty {
                    HStack(spacing: 20) {
                        Label("\(duplicateGroups.count) groups on this page", systemImage: "square.stack")
                        Label(formattedTotalSpace, systemImage: "externaldrive")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Toolbar
            HStack {
                // Sort options
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: sortOrder) { _, _ in
                    Task { await loadDuplicateGroups() }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Size filter
                HStack {
                    Text("Min size:")
                    Picker("", selection: $filterMinSize) {
                        Text("All").tag(0 as Int64)
                        Text("> 1 MB").tag(1_048_576 as Int64)
                        Text("> 10 MB").tag(10_485_760 as Int64)
                        Text("> 100 MB").tag(104_857_600 as Int64)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: filterMinSize) { _, _ in
                        Task { await loadDuplicateGroups() }
                    }
                }
                
                Spacer()
                
                Button("Refresh") {
                    Task { await loadDuplicateGroups() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if isLoading {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading duplicate groups...")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if duplicateGroups.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("No duplicates found")
                        .font(.title3)
                    Text("All your files are unique")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(duplicateGroups) { group in
                            OptimizedDuplicateGroupCard(group: group) {
                                selectedGroup = group
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadDuplicateGroups()
        }
        .sheet(item: $selectedGroup) { group in
            DuplicateDetailView(group: group)
        }
    }
    
    private var totalPages: Int {
        let total = totalGroups
        let size = pageSize
        return max(1, (total + size - 1) / size)
    }
    
    private var formattedTotalSpace: String {
        let totalSpace = duplicateGroups.reduce(0) { $0 + $1.potentialSpaceSaved }
        return ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file) + " can be saved"
    }
    
    private func previousPage() {
        currentPage = max(0, currentPage - 1)
        Task { await loadDuplicateGroups() }
    }
    
    private func nextPage() {
        currentPage = min(totalPages - 1, currentPage + 1)
        Task { await loadDuplicateGroups() }
    }
    
    private func loadDuplicateGroups() async {
        isLoading = true
        
        await Task.detached {
            let container = self.modelContext.container
            let context = ModelContext(container)
            
            // Get total count
            var countDescriptor = FetchDescriptor<DuplicateGroup>()
            if filterMinSize > 0 {
                countDescriptor.predicate = #Predicate { group in
                    group.fileSize >= filterMinSize
                }
            }
            let count = (try? context.fetchCount(countDescriptor)) ?? 0
            
            // Fetch current page
            var descriptor = FetchDescriptor<DuplicateGroup>()
            
            // Apply filter
            if filterMinSize > 0 {
                descriptor.predicate = #Predicate { group in
                    group.fileSize >= filterMinSize
                }
            }
            
            // Apply sort
            switch sortOrder {
            case .spaceSaved:
                // Sort by fileSize * (fileCount - 1) which represents potential space saved
                // Since we can't use computed properties, sort by fileSize and fileCount
                descriptor.sortBy = [
                    SortDescriptor(\.fileSize, order: .reverse),
                    SortDescriptor(\.fileCount, order: .reverse)
                ]
            case .fileCount:
                descriptor.sortBy = [SortDescriptor(\.fileCount, order: .reverse)]
            case .fileSize:
                descriptor.sortBy = [SortDescriptor(\.fileSize, order: .reverse)]
            }
            
            // Apply pagination
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = currentPage * pageSize
            
            let groups = (try? context.fetch(descriptor)) ?? []
            
            await MainActor.run {
                self.totalGroups = count
                self.duplicateGroups = groups
                self.isLoading = false
            }
        }
    }
}

struct OptimizedDuplicateGroupCard: View {
    let group: DuplicateGroup
    let onTap: () -> Void
    @State private var firstImageData: Data?
    @State private var isLoadingImage = true
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            ZStack {
                if let imageData = firstImageData,
                   let image = NSImage(data: imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(8)
                } else if isLoadingImage {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                } else {
                    Image(systemName: "photo.stack")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(group.files.count) duplicate files")
                        .font(.headline)
                    
                    if group.sha256Hash.hasPrefix("visual_") {
                        Label("Visual match", systemImage: "eye.fill")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(formatFileSize(group.fileSize))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("\(group.formattedSpaceSaved) can be saved")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onTapGesture(perform: onTap)
        .task {
            await loadThumbnail()
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private func loadThumbnail() async {
        guard let firstFile = group.files.first else { return }
        
        await Task.detached(priority: .background) {
            if let image = NSImage(contentsOf: firstFile.url) {
                let targetSize = CGSize(width: 160, height: 160) // 2x for retina
                if let thumbnailData = image.resized(to: targetSize)?.tiffRepresentation {
                    await MainActor.run {
                        self.firstImageData = thumbnailData
                        self.isLoadingImage = false
                    }
                }
            } else {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

extension NSImage {
    func resized(to newSize: CGSize) -> NSImage? {
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        bitmapRep.size = newSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let newImage = NSImage(size: newSize)
        newImage.addRepresentation(bitmapRep)
        return newImage
    }
}