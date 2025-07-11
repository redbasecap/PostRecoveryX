import SwiftUI
import SwiftData

struct DuplicateComparisonView: View {
    let group: DuplicateGroup
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ComparisonHeader(group: group, dismiss: dismiss)
            
            Divider()
            
            // Content
            GeometryReader { geometry in
                HStack(spacing: 20) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        FileComparisonColumn(
                            file: file,
                            geometry: geometry,
                            fileCount: group.files.count
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            ComparisonFooter(isPerceptualMatch: group.isPerceptualMatch, dismiss: dismiss)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct ComparisonHeader: View {
    let group: DuplicateGroup
    let dismiss: DismissAction
    
    var body: some View {
        HStack {
            Text("Compare Duplicates")
                .font(.title)
                .bold()
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct FileComparisonColumn: View {
    let file: ScannedFile
    let geometry: GeometryProxy
    let fileCount: Int
    
    var columnWidth: CGFloat {
        (geometry.size.width - CGFloat((fileCount - 1) * 20)) / CGFloat(fileCount)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // File info header
            FileInfoHeader(file: file)
            
            // Image preview
            RotationPreviewView(file: file)
                .frame(maxHeight: geometry.size.height - 200)
            
            Spacer()
        }
        .frame(width: columnWidth)
    }
}

struct FileInfoHeader: View {
    let file: ScannedFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if let rotation = file.suggestedRotation {
                    RotationIndicator(rotation: rotation)
                }
            }
            
            HStack {
                Label(file.formattedFileSize, systemImage: "doc")
                Spacer()
                if let date = file.originalCreationDate ?? file.creationDate {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if let dimensions = dimensionsText {
                Label(dimensions, systemImage: "aspectratio")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if file.hasMetadata {
                Label("Has metadata", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            if let camera = file.cameraModel {
                Label(camera, systemImage: "camera")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var dimensionsText: String? {
        guard let width = file.width, let height = file.height else { return nil }
        return "\(width) × \(height)"
    }
}

struct ComparisonFooter: View {
    let isPerceptualMatch: Bool
    let dismiss: DismissAction
    
    var body: some View {
        HStack {
            if isPerceptualMatch {
                Label("Visual match - Images may be rotated versions", systemImage: "rotate.right")
                    .foregroundColor(.orange)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    Text("Preview")
}