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