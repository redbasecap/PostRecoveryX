import SwiftUI

struct DuplicateWorkflowGuide: View {
    @Binding var showingGuide: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Duplicate Management Workflow")
                    .font(.title)
                    .bold()
                
                Spacer()
                
                Button(action: { showingGuide = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Overview
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Overview", systemImage: "info.circle")
                                .font(.headline)
                            
                            Text("PostRecoveryX helps you efficiently manage duplicate files by providing multiple resolution strategies and batch operations.")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Step by Step
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Step-by-Step Process", systemImage: "list.number")
                                .font(.headline)
                            
                            WorkflowStep(
                                number: 1,
                                title: "Review Duplicate Groups",
                                description: "Each card represents a group of identical files. Visual matches (rotated images) are marked with an orange badge."
                            )
                            
                            WorkflowStep(
                                number: 2,
                                title: "Select Groups to Process",
                                description: "Click the checkbox on each group you want to clean up. Use 'Select All' for batch operations."
                            )
                            
                            WorkflowStep(
                                number: 3,
                                title: "Choose Resolution Strategy",
                                description: "For each selected group, choose how to resolve duplicates:",
                                options: [
                                    "Keep Oldest - Preserves the original file",
                                    "Keep Newest - Keeps the most recent version",
                                    "Keep Largest - Retains the highest quality",
                                    "Keep Selected - Manually choose which file to keep",
                                    "Delete All - Remove all files in the group"
                                ]
                            )
                            
                            WorkflowStep(
                                number: 4,
                                title: "Review & Execute",
                                description: "Click 'Clean Up Selected' to move unwanted files to trash. You'll see a confirmation with the number of files and space to be recovered."
                            )
                        }
                    }
                    
                    // Advanced Options
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Advanced Options", systemImage: "gearshape.2")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                BulletPoint(
                                    icon: "rectangle.split.2x1",
                                    text: "Compare - View files side by side to make informed decisions"
                                )
                                
                                BulletPoint(
                                    icon: "arrow.triangle.merge",
                                    text: "Merge Metadata - Combine the best metadata from duplicate files"
                                )
                                
                                BulletPoint(
                                    icon: "square.grid.3x3",
                                    text: "Apply Resolution to All - Apply the same strategy to all selected groups"
                                )
                            }
                        }
                    }
                    
                    // Safety
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Safety Features", systemImage: "shield")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                BulletPoint(
                                    icon: "trash",
                                    text: "Files are moved to Trash, not permanently deleted",
                                    color: .green
                                )
                                
                                BulletPoint(
                                    icon: "exclamationmark.triangle",
                                    text: "Warning shown when deleting all files in a group",
                                    color: .orange
                                )
                                
                                BulletPoint(
                                    icon: "arrow.uturn.backward",
                                    text: "You can restore files from Trash if needed",
                                    color: .blue
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Got it!") {
                    showingGuide = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
    }
}

struct WorkflowStep: View {
    let number: Int
    let title: String
    let description: String
    var options: [String] = []
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 30, height: 30)
                
                Text("\(number)")
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .foregroundColor(.secondary)
                
                if !options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options, id: \.self) { option in
                            HStack(spacing: 8) {
                                Text("•")
                                    .foregroundColor(.accentColor)
                                Text(option)
                                    .font(.caption)
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct BulletPoint: View {
    let icon: String
    let text: String
    var color: Color = .primary
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}