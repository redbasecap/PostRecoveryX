import SwiftUI
import AppKit

struct RotationPreviewView: View {
    let file: ScannedFile
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var showRotated = false
    
    var rotationAngle: Double {
        guard let rotation = file.suggestedRotation else { return 0 }
        return Double(rotation)
    }
    
    var rotationText: String {
        guard let rotation = file.suggestedRotation else { return "" }
        let absRotation = abs(rotation)
        let direction = rotation > 0 ? "clockwise" : "counter-clockwise"
        return "\(absRotation)° \(direction)"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Image preview with rotation
            GeometryReader { geometry in
                if let image = image {
                    ZStack {
                        // Original image (faded)
                        if showRotated && file.suggestedRotation != nil {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .opacity(0.3)
                        }
                        
                        // Rotated image
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(showRotated ? rotationAngle : 0))
                            .animation(.easeInOut(duration: 0.5), value: showRotated)
                    }
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else if isLoading {
                    ProgressView("Loading image...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("Unable to load image")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Rotation info and controls
            if file.suggestedRotation != nil {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "rotate.right")
                            .foregroundColor(.blue)
                        Text("Suggested rotation: \(rotationText)")
                            .font(.headline)
                    }
                    
                    Toggle("Show rotated preview", isOn: $showRotated)
                        .toggleStyle(.switch)
                    
                    Text("This image appears to be rotated compared to its duplicate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let loadedImage = NSImage(contentsOf: file.url) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

