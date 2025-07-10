import SwiftUI
import SwiftData

struct OrganizationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var scannedFiles: [ScannedFile]
    @StateObject private var viewModel = OrganizationViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("File Organization")
                .font(.largeTitle)
                .bold()
            
            Text("Organize your files into a clean folder structure")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical)
            
            GroupBox("Output Settings") {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Destination Folder:")
                        Spacer()
                        TextField("Select output folder...", text: $viewModel.outputPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .frame(maxWidth: 300)
                        
                        Button("Browse...") {
                            viewModel.selectOutputFolder()
                        }
                        .disabled(viewModel.isOrganizing)
                    }
                    
                    HStack {
                        Text("Organization Mode:")
                        Spacer()
                        Picker("", selection: $viewModel.organizationMode) {
                            Text("By Year").tag(OrganizationMode.byYear)
                            Text("By Month").tag(OrganizationMode.byMonth)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    HStack {
                        Text("File Action:")
                        Spacer()
                        Picker("", selection: $viewModel.fileAction) {
                            Text("Copy Files").tag(OrganizationAction.copy)
                            Text("Move Files").tag(OrganizationAction.move)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    Toggle("Rename files with date prefix", isOn: $viewModel.renameFilesWithDate)
                        .help("Adds YYYY-MM-DD prefix to filenames based on creation date")
                }
                .padding()
            }
            .padding(.horizontal, 40)
            
            if viewModel.organizationMode == .byMonth {
                Text("Files will be organized into: Year/Month/OriginalFolder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Files will be organized into: Year/OriginalFolder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if viewModel.isOrganizing {
                VStack(spacing: 10) {
                    ProgressView(value: viewModel.organizationProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                    
                    Text(viewModel.organizationStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Cancel") {
                        Task {
                            await viewModel.cancelOrganization()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 10) {
                    Text("\(scannedFiles.count) files available for organization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Organize Files") {
                        Task {
                            await viewModel.organizeFiles(scannedFiles, modelContext: modelContext)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.outputPath.isEmpty || scannedFiles.isEmpty)
                }
            }
            
            if let summary = viewModel.organizationSummary {
                GroupBox("Organization Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Files Organized:")
                            Spacer()
                            Text("\(summary.filesOrganized)")
                        }
                        HStack {
                            Text("Folders Created:")
                            Spacer()
                            Text("\(summary.foldersCreated)")
                        }
                        if summary.errors > 0 {
                            HStack {
                                Text("Errors:")
                                Spacer()
                                Text("\(summary.errors)")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

enum OrganizationMode: String, CaseIterable {
    case byYear = "Year"
    case byMonth = "Month"
}

struct OrganizationSummary {
    let filesOrganized: Int
    let foldersCreated: Int
    let errors: Int
}

#Preview {
    OrganizationView()
        .modelContainer(for: [
            ScannedFile.self,
            OrganizationTask.self
        ], inMemory: true)
}