import SwiftUI
import QuickLook
import QuickLookThumbnailing
import AppKit

// Simplified image view for the comparison
struct SimpleImageView: View {
    let url: URL
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { oldValue, newValue in
            loadImage()
        }
    }
    
    private func loadImage() {
        image = nil  // Clear previous image
        DispatchQueue.global(qos: .userInitiated).async {
            if let nsImage = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    self.image = nsImage
                }
            }
        }
    }
}

struct DuplicateComparisonView: View {
    let group: DuplicateGroup
    @State private var selectedIndices: Set<Int> = []
    @State private var currentIndex = 0
    @State private var showingFullPreview = false
    @State private var zoomScale: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss
    
    var urls: [URL] {
        group.files.map { $0.url }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Duplicate Comparison")
                        .font(.title2)
                        .bold()
                    Text("\(group.files.count) similar images found")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Main comparison view
            GeometryReader { geometry in
                HStack(spacing: 20) {
                    ForEach(0..<min(2, group.files.count), id: \.self) { index in
                        VStack {
                            // Image preview
                            ZStack {
                                if let image = NSImage(contentsOf: group.files[index].url) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .scaleEffect(zoomScale)
                                        .frame(maxWidth: geometry.size.width / 2 - 30)
                                        .background(Color.black.opacity(0.1))
                                        .cornerRadius(8)
                                        .onTapGesture(count: 2) {
                                            withAnimation {
                                                zoomScale = zoomScale == 1.0 ? 2.0 : 1.0
                                            }
                                        }
                                        .onTapGesture {
                                            currentIndex = index
                                            showingFullPreview = true
                                        }
                                } else {
                                    ProgressView()
                                        .frame(width: geometry.size.width / 2 - 30, height: 300)
                                }
                            }
                            
                            // File info
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(group.files[index].fileName, systemImage: "doc")
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Label(group.files[index].formattedFileSize, systemImage: "scalemass")
                                        Spacer()
                                        if let dimensions = imageDimensions(for: group.files[index]) {
                                            Label(dimensions, systemImage: "aspectratio")
                                        }
                                    }
                                    .font(.caption)
                                    
                                    if let date = group.files[index].originalCreationDate ?? group.files[index].creationDate {
                                        Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                            .font(.caption)
                                    }
                                    
                                    if group.files[index].hasMetadata {
                                        Label("Contains EXIF metadata", systemImage: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    
                                    if let camera = group.files[index].cameraModel {
                                        Label(camera, systemImage: "camera")
                                            .font(.caption)
                                    }
                                }
                            }
                            .frame(width: geometry.size.width / 2 - 30)
                        }
                    }
                }
                .padding()
                
                // Navigation arrows for more than 2 files
                if group.files.count > 2 {
                    HStack {
                        Button(action: previousPair) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                        }
                        .disabled(currentIndex == 0)
                        .opacity(currentIndex == 0 ? 0.3 : 1)
                        
                        Spacer()
                        
                        Button(action: nextPair) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                        }
                        .disabled(currentIndex >= group.files.count - 2)
                        .opacity(currentIndex >= group.files.count - 2 ? 0.3 : 1)
                    }
                    .padding(.horizontal, 40)
                }
            }
            
            // Bottom toolbar
            HStack {
                Text("Viewing \(currentIndex + 1)-\(min(currentIndex + 2, group.files.count)) of \(group.files.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { zoomScale = 1.0 }) {
                        Label("Reset Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(zoomScale == 1.0)
                    
                    Button(action: { showingFullPreview = true }) {
                        Label("Full Preview", systemImage: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingFullPreview) {
            QuickLookPreview(urls: urls, currentIndex: $currentIndex)
        }
    }
    
    private func previousPair() {
        withAnimation {
            currentIndex = max(0, currentIndex - 2)
        }
    }
    
    private func nextPair() {
        withAnimation {
            currentIndex = min(group.files.count - 2, currentIndex + 2)
        }
    }
    
    private func imageDimensions(for file: ScannedFile) -> String? {
        guard let width = file.width, let height = file.height else { return nil }
        return "\(width) × \(height)"
    }
}

struct QuickLookPreview: View {
    let urls: [URL]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview \(currentIndex + 1) of \(urls.count)")
                    .font(.headline)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Image preview
            if !urls.isEmpty && currentIndex < urls.count {
                SimpleImageView(url: urls[currentIndex])
                    .id(currentIndex)  // Force view recreation on index change
                    .frame(minWidth: 800, minHeight: 600)
                    .background(Color.black.opacity(0.9))
            }
            
            Divider()
            
            // Navigation controls
            HStack(spacing: 40) {
                Button(action: { currentIndex = max(0, currentIndex - 1) }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                }
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow)
                .buttonStyle(.plain)
                
                VStack {
                    Text("\(urls[currentIndex].lastPathComponent)")
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 300)
                    
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: urls[currentIndex].path),
                       let fileSize = attributes[.size] as? Int64 {
                        let formatter = ByteCountFormatter()
                        let sizeString = formatter.string(fromByteCount: fileSize)
                        Text(sizeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: { currentIndex = min(urls.count - 1, currentIndex + 1) }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                }
                .disabled(currentIndex >= urls.count - 1)
                .keyboardShortcut(.rightArrow)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}