import SwiftUI
import SwiftData

struct ThumbnailManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ScannedFile> { file in
        file.isThumbnail == true
    }) private var thumbnails: [ScannedFile]
    
    @State private var selectedThumbnails: Set<ScannedFile> = []
    @State private var showingDeleteConfirmation = false
    @State private var sortOrder = SortOrder.size
    @State private var isDeleting = false
    
    enum SortOrder: String, CaseIterable {
        case size = "Size"
        case name = "Name"
        case date = "Date"
    }
    
    var sortedThumbnails: [ScannedFile] {
        switch sortOrder {
        case .size:
            return thumbnails.sorted { $0.fileSize < $1.fileSize }
        case .name:
            return thumbnails.sorted { $0.fileName < $1.fileName }
        case .date:
            return thumbnails.sorted { ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) }
        }
    }
    
    var totalSize: Int64 {
        thumbnails.reduce(0) { $0 + $1.fileSize }
    }
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Thumbnail Management")
                        .font(.title2)
                        .bold()
                    Text("\(thumbnails.count) thumbnails found • \(formattedTotalSize) total")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()
            
            Divider()
            
            // Toolbar
            HStack {
                Button("Select All") {
                    selectedThumbnails = Set(thumbnails)
                }
                .disabled(thumbnails.isEmpty)
                
                Button("Deselect All") {
                    selectedThumbnails.removeAll()
                }
                .disabled(selectedThumbnails.isEmpty)
                
                Spacer()
                
                Text("\(selectedThumbnails.count) selected")
                    .foregroundColor(.secondary)
                
                Button("Delete Selected") {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedThumbnails.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Thumbnail grid
            if thumbnails.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No thumbnails found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Thumbnails are typically small images (under 10KB) or images with small dimensions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                        ForEach(sortedThumbnails) { thumbnail in
                            ThumbnailItemView(
                                file: thumbnail,
                                isSelected: selectedThumbnails.contains(thumbnail)
                            ) {
                                if selectedThumbnails.contains(thumbnail) {
                                    selectedThumbnails.remove(thumbnail)
                                } else {
                                    selectedThumbnails.insert(thumbnail)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("Delete Thumbnails", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteThumbnails()
                }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedThumbnails.count) thumbnail\(selectedThumbnails.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .overlay {
            if isDeleting {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Deleting thumbnails...")
                        .font(.headline)
                }
                .padding(40)
                .background(.regularMaterial)
                .cornerRadius(12)
            }
        }
    }
    
    private func deleteThumbnails() async {
        isDeleting = true
        
        let filesToDelete = Array(selectedThumbnails)
        var deletedCount = 0
        
        for file in filesToDelete {
            do {
                try FileManager.default.removeItem(at: file.url)
                modelContext.delete(file)
                deletedCount += 1
            } catch {
                print("Failed to delete \(file.fileName): \(error)")
            }
        }
        
        do {
            try modelContext.save()
            selectedThumbnails.removeAll()
        } catch {
            print("Failed to save context: \(error)")
        }
        
        isDeleting = false
    }
}

struct ThumbnailItemView: View {
    let file: ScannedFile
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var thumbnail: NSImage?
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail preview
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
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(.white))
                        .padding(8)
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Text(file.formattedFileSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let width = file.width, let height = file.height {
                        Text("• \(width)×\(height)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 150, alignment: .leading)
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

#Preview {
    ThumbnailManagementView()
        .modelContainer(for: [
            ScannedFile.self,
            DuplicateGroup.self
        ], inMemory: true)
}