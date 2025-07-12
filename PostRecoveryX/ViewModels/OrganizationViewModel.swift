import Foundation
import SwiftUI
import SwiftData
import AppKit

enum FileNamingMode: String, CaseIterable {
    case keepOriginal = "Keep Original"
    case datePrefix = "Add Date Prefix"
    case fullRename = "Full Date Rename"
}

@MainActor
class OrganizationViewModel: ObservableObject {
    @Published var outputPath: String = ""
    @Published var organizationMode: OrganizationMode = .byMonth
    @Published var fileAction: OrganizationAction = .copy
    @Published var fileNamingMode: FileNamingMode = .keepOriginal
    @Published var isOrganizing = false
    @Published var organizationProgress: Double = 0.0
    @Published var organizationStatus: String = ""
    @Published var organizationSummary: OrganizationSummary?
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let folderOrganizer = FolderOrganizer()
    private var organizationTasks: [OrganizationTask] = []
    private var dateCollisionTracker: [String: Int] = [:] // Track files with same timestamp
    
    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select output folder for organized files"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                outputPath = url.path
            }
        }
    }
    
    func organizeFiles(_ files: [ScannedFile], modelContext: ModelContext) async {
        guard !outputPath.isEmpty else { return }
        
        isOrganizing = true
        organizationProgress = 0.0
        organizationStatus = "Preparing files..."
        organizationSummary = nil
        
        do {
            let filesToOrganize = files.filter { file in
                file.isProcessed && (file.originalCreationDate != nil || file.creationDate != nil)
            }
            
            if filesToOrganize.isEmpty {
                throw OrganizationError.noFilesWithDates
            }
            
            organizationStatus = "Creating organization plan..."
            
            let tasks = try await createOrganizationTasks(
                for: filesToOrganize,
                to: URL(fileURLWithPath: outputPath),
                modelContext: modelContext
            )
            
            organizationTasks = tasks
            
            organizationStatus = "Organizing \(tasks.count) files..."
            
            let (organized, errors) = await executeOrganizationTasks(tasks)
            
            let foldersCreated = Set(tasks.map { URL(fileURLWithPath: $0.destinationPath).path }).count
            
            organizationSummary = OrganizationSummary(
                filesOrganized: organized,
                foldersCreated: foldersCreated,
                errors: errors
            )
            
            organizationProgress = 1.0
            organizationStatus = "Organization complete!"
            
            try modelContext.save()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            organizationStatus = "Organization failed"
        }
        
        isOrganizing = false
    }
    
    private func createOrganizationTasks(
        for files: [ScannedFile],
        to destinationRoot: URL,
        modelContext: ModelContext
    ) async throws -> [OrganizationTask] {
        var tasks: [OrganizationTask] = []
        dateCollisionTracker.removeAll() // Reset collision tracker
        
        // Sort files by date to ensure consistent naming
        let sortedFiles = files.sorted { file1, file2 in
            let date1 = file1.originalCreationDate ?? file1.creationDate ?? Date.distantPast
            let date2 = file2.originalCreationDate ?? file2.creationDate ?? Date.distantPast
            return date1 < date2
        }
        
        for file in sortedFiles {
            let organizationPath = getOrganizationPath(for: file)
            let destinationDir = destinationRoot.appendingPathComponent(organizationPath)
            
            let fileName = getFileName(for: file)
            
            let task = OrganizationTask(
                sourcePath: file.path,
                destinationPath: destinationDir.path,
                fileName: fileName,
                action: fileAction
            )
            
            modelContext.insert(task)
            tasks.append(task)
        }
        
        return tasks
    }
    
    private func getOrganizationPath(for file: ScannedFile) -> String {
        guard let date = file.originalCreationDate ?? file.creationDate else {
            return "Unknown Date"
        }
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        // When using date-based naming, don't create subfolders for original folders
        if fileNamingMode != .keepOriginal {
            switch organizationMode {
            case .byYear:
                return "\(year)"
            case .byMonth:
                let month = calendar.component(.month, from: date)
                let monthName = DateFormatter().monthSymbols[month - 1]
                return "\(year)/\(String(format: "%02d", month)) - \(monthName)"
            }
        } else {
            // Keep original behavior when not renaming
            let topFolder = file.url.deletingLastPathComponent().lastPathComponent
            
            switch organizationMode {
            case .byYear:
                return "\(year)/\(topFolder)"
            case .byMonth:
                let month = calendar.component(.month, from: date)
                let monthName = DateFormatter().monthSymbols[month - 1]
                return "\(year)/\(String(format: "%02d", month)) - \(monthName)/\(topFolder)"
            }
        }
    }
    
    private func getFileName(for file: ScannedFile) -> String {
        switch fileNamingMode {
        case .keepOriginal:
            return file.fileName
        case .datePrefix:
            return getDatePrefixedFileName(for: file)
        case .fullRename:
            return getFullyRenamedFileName(for: file)
        }
    }
    
    private func getDatePrefixedFileName(for file: ScannedFile) -> String {
        guard let date = file.originalCreationDate ?? file.creationDate else {
            return file.fileName
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let datePrefix = dateFormatter.string(from: date)
        
        let url = URL(fileURLWithPath: file.path)
        let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        
        if fileExtension.isEmpty {
            return "\(datePrefix)_\(nameWithoutExtension)"
        } else {
            return "\(datePrefix)_\(nameWithoutExtension).\(fileExtension)"
        }
    }
    
    private func getFullyRenamedFileName(for file: ScannedFile) -> String {
        guard let date = file.originalCreationDate ?? file.creationDate else {
            return file.fileName
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: date)
        
        let url = URL(fileURLWithPath: file.path)
        let fileExtension = url.pathExtension
        
        // Check for collisions with same timestamp
        let baseKey = dateString
        let count = dateCollisionTracker[baseKey] ?? 0
        dateCollisionTracker[baseKey] = count + 1
        
        // If multiple files have same timestamp, add a hash suffix
        if count > 0 {
            // Use first 6 characters of SHA256 hash for uniqueness
            let hashSuffix = String(file.sha256Hash?.prefix(6) ?? "\(count)")
            if fileExtension.isEmpty {
                return "\(dateString)_\(hashSuffix)"
            } else {
                return "\(dateString)_\(hashSuffix).\(fileExtension)"
            }
        } else {
            // First file with this timestamp gets clean name
            if fileExtension.isEmpty {
                return dateString
            } else {
                return "\(dateString).\(fileExtension)"
            }
        }
    }
    
    private func executeOrganizationTasks(_ tasks: [OrganizationTask]) async -> (organized: Int, errors: Int) {
        var organized = 0
        var errors = 0
        let totalTasks = Double(tasks.count)
        
        for (index, task) in tasks.enumerated() {
            do {
                try await task.execute()
                organized += 1
            } catch {
                errors += 1
                task.error = error.localizedDescription
            }
            
            organizationProgress = Double(index + 1) / totalTasks
            organizationStatus = "Organizing files... (\(index + 1)/\(Int(totalTasks)))"
        }
        
        return (organized, errors)
    }
    
    func cancelOrganization() async {
        await folderOrganizer.cancel()
        
        for task in organizationTasks where task.status == .pending {
            task.status = .cancelled
        }
        
        isOrganizing = false
        organizationStatus = "Organization cancelled"
    }
}

enum OrganizationError: LocalizedError {
    case noFilesWithDates
    
    var errorDescription: String? {
        switch self {
        case .noFilesWithDates:
            return "No files found with valid creation dates for organization"
        }
    }
}