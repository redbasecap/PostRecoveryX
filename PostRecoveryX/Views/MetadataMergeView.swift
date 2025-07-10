import SwiftUI
import SwiftData

struct MetadataMergeView: View {
    let recommendation: MetadataMerger.MergeRecommendation
    let group: DuplicateGroup
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingSuccessAlert = false
    @State private var applyError: String?
    
    private let metadataMerger = MetadataMerger()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text("Metadata Merge Suggestions")
                            .font(.title)
                            .bold()
                        Text("Combine the best metadata from both files")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                
                Divider()
            }
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // File Summary
                    GroupBox("Files") {
                        VStack(spacing: 12) {
                            FileInfoRow(
                                label: "Target (Keep):",
                                file: recommendation.targetFile,
                                isTarget: true
                            )
                            
                            FileInfoRow(
                                label: "Source (Delete):",
                                file: recommendation.sourceFile,
                                isTarget: false
                            )
                        }
                    }
                    
                    // Metadata Recommendations
                    GroupBox("Metadata Recommendations") {
                        VStack(spacing: 16) {
                            ForEach(recommendation.recommendations, id: \.field) { rec in
                                MetadataFieldRow(recommendation: rec)
                            }
                        }
                    }
                    
                    // Summary
                    if recommendation.mergedMetadata.hasCompleteMetadata {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Merging will result in complete metadata")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Suggested filename
                    if recommendation.mergedMetadata.bestFileName != recommendation.targetFile.fileName {
                        GroupBox("Suggested Filename") {
                            HStack {
                                Text("Current:")
                                Text(recommendation.targetFile.fileName)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            
                            HStack {
                                Text("Suggested:")
                                Text(recommendation.mergedMetadata.bestFileName)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
            }
            
            // Footer
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Apply Metadata Merge") {
                        applyMetadataMerge()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Metadata has been successfully merged to the target file.")
        }
        .alert("Error", isPresented: .constant(applyError != nil)) {
            Button("OK") {
                applyError = nil
            }
        } message: {
            Text(applyError ?? "")
        }
    }
    
    private func applyMetadataMerge() {
        do {
            // Apply the merged metadata to the target file
            metadataMerger.applyMergedMetadata(
                recommendation.mergedMetadata,
                to: recommendation.targetFile
            )
            
            // Save the changes
            try modelContext.save()
            
            showingSuccessAlert = true
        } catch {
            applyError = "Failed to apply metadata: \(error.localizedDescription)"
        }
    }
}

struct FileInfoRow: View {
    let label: String
    let file: ScannedFile
    let isTarget: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.headline)
                .frame(width: 120, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.fileName)
                        .font(.system(.body, design: .monospaced))
                    
                    if isTarget {
                        Label("Keep", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                HStack {
                    if let date = file.originalCreationDate ?? file.creationDate {
                        Label(date.formatted(), systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let camera = file.cameraModel {
                        Label(camera, systemImage: "camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct MetadataFieldRow: View {
    let recommendation: MetadataMerger.MetadataRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recommendation.field)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatValue(recommendation.sourceValue))
                        .font(.system(.body, design: .monospaced))
                }
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatValue(recommendation.targetValue))
                        .font(.system(.body, design: .monospaced))
                }
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatValue(recommendation.recommendedValue))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            
            Text(recommendation.reason)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "None" }
        
        if let date = value as? Date {
            return date.formatted()
        } else if let dimensions = value as? (Int, Int) {
            return "\(dimensions.0) × \(dimensions.1)"
        } else {
            return String(describing: value)
        }
    }
}