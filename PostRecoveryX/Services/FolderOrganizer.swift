import Foundation
import SwiftData

actor FolderOrganizer {
    private var isCancelled = false
    private var progress: Progress?
    
    func organizeFiles(
        _ files: [ScannedFile],
        to destinationRoot: URL,
        action: OrganizationAction = .copy,
        modelContext: ModelContext
    ) async throws -> [OrganizationTask] {
        isCancelled = false
        progress = Progress(totalUnitCount: Int64(files.count))
        
        var tasks: [OrganizationTask] = []
        
        for file in files {
            if isCancelled {
                throw FolderOrganizerError.cancelled
            }
            
            guard let organizationPath = file.suggestedOrganizationPath else {
                continue
            }
            
            let destinationDir = destinationRoot.appendingPathComponent(organizationPath)
            
            let task = OrganizationTask(
                sourcePath: file.path,
                destinationPath: destinationDir.path,
                fileName: await resolveFileName(file.fileName, at: destinationDir),
                action: action
            )
            
            modelContext.insert(task)
            tasks.append(task)
            
            progress?.completedUnitCount += 1
        }
        
        try modelContext.save()
        return tasks
    }
    
    func executeTasks(_ tasks: [OrganizationTask]) async throws {
        progress = Progress(totalUnitCount: Int64(tasks.count))
        
        for task in tasks where task.status == .pending {
            if isCancelled {
                task.status = .cancelled
                throw FolderOrganizerError.cancelled
            }
            
            do {
                try await task.execute()
                progress?.completedUnitCount += 1
            } catch {
                continue
            }
        }
    }
    
    func resolveConflicts(
        in duplicateGroups: [DuplicateGroup],
        modelContext: ModelContext
    ) async throws -> [URL] {
        var filesToDelete: [URL] = []
        
        for group in duplicateGroups where group.isResolved {
            guard let action = group.resolutionAction else { continue }
            
            var fileToKeep: ScannedFile?
            
            switch action {
            case .keepOldest:
                fileToKeep = group.oldestFile
            case .keepNewest:
                fileToKeep = group.newestFile
            case .keepLargest:
                fileToKeep = group.largestFile
            case .keepSelected:
                if let selectedID = group.selectedFileID {
                    fileToKeep = group.files.first { $0.id == selectedID }
                }
            case .keepAll:
                continue
            }
            
            guard let keepFile = fileToKeep else { continue }
            
            for file in group.files where file.id != keepFile.id {
                filesToDelete.append(file.url)
            }
        }
        
        return filesToDelete
    }
    
    func deleteFiles(_ urls: [URL]) async throws {
        progress = Progress(totalUnitCount: Int64(urls.count))
        
        for url in urls {
            if isCancelled {
                throw FolderOrganizerError.cancelled
            }
            
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                progress?.completedUnitCount += 1
            } catch {
                continue
            }
        }
    }
    
    private func resolveFileName(_ originalName: String, at directory: URL) async -> String {
        let fileManager = FileManager.default
        var finalName = originalName
        var counter = 1
        
        let nameWithoutExtension = (originalName as NSString).deletingPathExtension
        let fileExtension = (originalName as NSString).pathExtension
        
        while fileManager.fileExists(atPath: directory.appendingPathComponent(finalName).path) {
            if fileExtension.isEmpty {
                finalName = "\(nameWithoutExtension) \(counter)"
            } else {
                finalName = "\(nameWithoutExtension) \(counter).\(fileExtension)"
            }
            counter += 1
        }
        
        return finalName
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func currentProgress() -> Progress? {
        progress
    }
}

enum FolderOrganizerError: LocalizedError {
    case cancelled
    case cannotCreateDirectory
    case fileOperationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Organization was cancelled"
        case .cannotCreateDirectory:
            return "Cannot create destination directory"
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        }
    }
}