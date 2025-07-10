import SwiftUI
import SwiftData
import QuickLookThumbnailing

struct DuplicateDetailView: View {
    @Bindable var group: DuplicateGroup
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFileID: UUID?
    @State private var showingOrganizeSheet = false
    @State private var thumbnails: [UUID: NSImage] = [:]
    
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    Text("Duplicate Group")
                        .font(.title2)
                        .bold()
                    
                    Text("\(group.files.count) files • \(group.formattedSpaceSaved) potential savings")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !group.isResolved {
                    Menu("Resolution Action") {
                        ForEach(ResolutionAction.allCases, id: \.self) { action in
                            Button(action.rawValue) {
                                group.resolutionAction = action
                                if action != .keepSelected {
                                    resolveGroup()
                                }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                }
            }
            .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                    ForEach(group.files) { file in
                        FileCard(
                            file: file,
                            isSelected: selectedFileID == file.id || shouldHighlight(file),
                            thumbnail: thumbnails[file.id]
                        ) {
                            selectedFileID = file.id
                            group.selectedFileID = file.id
                            if group.resolutionAction == .keepSelected {
                                resolveGroup()
                            }
                        }
                    }
                }
                .padding()
            }
            
            if group.isResolved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Resolved: \(group.resolutionAction?.rawValue ?? "Unknown")")
                    Spacer()
                    Button("Undo") {
                        group.isResolved = false
                        group.resolutionAction = nil
                        group.selectedFileID = nil
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
            }
        }
        .onAppear {
            loadThumbnails()
        }
    }
    
    private func shouldHighlight(_ file: ScannedFile) -> Bool {
        guard group.isResolved, let action = group.resolutionAction else { return false }
        
        switch action {
        case .keepOldest:
            return file.id == group.oldestFile?.id
        case .keepNewest:
            return file.id == group.newestFile?.id
        case .keepLargest:
            return file.id == group.largestFile?.id
        case .keepSelected:
            return file.id == group.selectedFileID
        case .keepAll:
            return true
        }
    }
    
    private func resolveGroup() {
        group.isResolved = true
        try? modelContext.save()
    }
    
    private func loadThumbnails() {
        let size = CGSize(width: 200, height: 200)
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        
        for file in group.files {
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

struct FileCard: View {
    let file: ScannedFile
    let isSelected: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                } else {
                    ProgressView()
                }
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .onTapGesture(perform: onTap)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(file.formattedFileSize)
                    Spacer()
                    if let date = file.originalCreationDate ?? file.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                
                if file.hasMetadata {
                    Label("Has metadata", systemImage: "info.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(12)
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