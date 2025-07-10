import Foundation
import SwiftData

@Model
final class OrganizationTask {
    var id: UUID
    var sourcePath: String
    var destinationPath: String
    var fileName: String
    var action: OrganizationAction
    var status: TaskStatus
    var createdAt: Date
    var completedAt: Date?
    var error: String?
    
    init(sourcePath: String, destinationPath: String, fileName: String, action: OrganizationAction) {
        self.id = UUID()
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.fileName = fileName
        self.action = action
        self.status = .pending
        self.createdAt = Date()
    }
}

enum OrganizationAction: String, Codable, CaseIterable {
    case copy = "Copy"
    case move = "Move"
}

enum TaskStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

extension OrganizationTask {
    var sourceURL: URL {
        URL(fileURLWithPath: sourcePath)
    }
    
    var destinationURL: URL {
        URL(fileURLWithPath: destinationPath).appendingPathComponent(fileName)
    }
    
    func execute() async throws {
        status = .inProgress
        
        do {
            let fileManager = FileManager.default
            
            try fileManager.createDirectory(at: URL(fileURLWithPath: destinationPath), 
                                          withIntermediateDirectories: true)
            
            switch action {
            case .copy:
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            case .move:
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            
            status = .completed
            completedAt = Date()
        } catch {
            status = .failed
            self.error = error.localizedDescription
            throw error
        }
    }
}