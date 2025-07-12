import SwiftUI
import SwiftData

struct FileTypeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var filter = FileTypeFilter()
    let onComplete: () async -> Void
    
    @Query private var scannedFiles: [ScannedFile]
    @State private var customExtension = ""
    @State private var fileTypeCounts: [String: Int] = [:]
    @State private var isProcessing = false
    
    var totalFiles: Int {
        scannedFiles.count
    }
    
    var selectedFileCount: Int {
        scannedFiles.filter { file in
            filter.shouldInclude(fileType: file.fileType)
        }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Select File Types to Process")
                    .font(.title)
                    .bold()
                
                Text("\(totalFiles) files found • \(selectedFileCount) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Quick actions
                    HStack(spacing: 12) {
                        Button("Select All") {
                            filter.enableAll()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Select None") {
                            filter.disableAll()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // File type categories
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(FileTypeCategory.allCategories, id: \.id) { category in
                            FileTypeCategoryCard(
                                category: category,
                                isSelected: filter.enabledCategories.contains(category),
                                fileCount: countFiles(for: category)
                            ) {
                                filter.toggle(category)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Custom extensions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom File Extensions")
                            .font(.headline)
                        
                        Text("Add specific file extensions not covered above")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("e.g., xyz, abc", text: $customExtension)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addCustomExtension()
                                }
                            
                            Button("Add") {
                                addCustomExtension()
                            }
                            .disabled(customExtension.isEmpty)
                        }
                        
                        if !filter.customExtensions.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(filter.customExtensions), id: \.self) { ext in
                                    HStack(spacing: 4) {
                                        Text(".\(ext)")
                                            .font(.caption)
                                        
                                        Button {
                                            filter.customExtensions.remove(ext)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if selectedFileCount == 0 {
                    Text("Select at least one file type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Process \(selectedFileCount) Files") {
                    Task {
                        isProcessing = true
                        await onComplete()
                        isProcessing = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFileCount == 0 || isProcessing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .onAppear {
            calculateFileTypeCounts()
        }
    }
    
    private func calculateFileTypeCounts() {
        var counts: [String: Int] = [:]
        
        for file in scannedFiles {
            let ext = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            counts[ext, default: 0] += 1
        }
        
        fileTypeCounts = counts
    }
    
    private func countFiles(for category: FileTypeCategory) -> Int {
        scannedFiles.filter { file in
            category.matches(fileType: file.fileType)
        }.count
    }
    
    private func addCustomExtension() {
        let ext = customExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        
        if !ext.isEmpty {
            filter.customExtensions.insert(ext)
            customExtension = ""
        }
    }
}

struct FileTypeCategoryCard: View {
    let category: FileTypeCategory
    let isSelected: Bool
    let fileCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.largeTitle)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(category.name)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text("\(fileCount) files")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Simple flow layout for custom extensions
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.frames[index].minX + bounds.minX,
                                     y: result.frames[index].minY + bounds.minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let dimensions = subview.dimensions(in: .unspecified)
                
                if currentX + dimensions.width > maxWidth && currentX > 0 {
                    currentY += lineHeight + spacing
                    currentX = 0
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: dimensions.width, height: dimensions.height))
                lineHeight = max(lineHeight, dimensions.height)
                currentX += dimensions.width + spacing
                maxX = max(maxX, currentX)
            }
            
            size = CGSize(width: maxX - spacing, height: currentY + lineHeight)
        }
    }
}