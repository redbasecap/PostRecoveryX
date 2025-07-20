import Foundation

// Sendable data transfer types for passing data across actor boundaries

struct SessionInfo: Sendable {
    let id: UUID
    let scanPath: String
    let status: SessionStatus
}

struct FileInfo: Sendable {
    let id: UUID
    let path: String
    let fileName: String
    let fileType: String
}

struct DuplicateGroupInfo: Sendable {
    let id: UUID
    let fileCount: Int
    let potentialSpaceSaved: Int64
}

struct SceneGroupInfo: Sendable {
    let id: UUID
    let fileCount: Int
}