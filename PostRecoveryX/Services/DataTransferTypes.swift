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

// File type filtering support (Sendable version)
struct SimpleFileTypeFilter: Sendable {
    let selectedTypes: Set<String>
    let discoveredTypes: [String]
    
    init(selectedTypes: Set<String> = [], discoveredTypes: [String] = []) {
        self.selectedTypes = selectedTypes
        self.discoveredTypes = discoveredTypes
    }
    
    var hasSelection: Bool {
        !selectedTypes.isEmpty
    }
    
    func updateDiscoveredTypes(_ types: [String]) -> SimpleFileTypeFilter {
        let sortedTypes = types.sorted()
        // By default, select common image/video types
        let commonTypes = ["jpg", "jpeg", "png", "heic", "mp4", "mov", "avi"]
        let newSelectedTypes = Set(types.filter { commonTypes.contains($0.lowercased()) })
        return SimpleFileTypeFilter(selectedTypes: newSelectedTypes, discoveredTypes: sortedTypes)
    }
    
    func shouldInclude(fileType: String?) -> Bool {
        guard let type = fileType else { return false }
        return selectedTypes.contains(type.lowercased())
    }
    
    func toggle(_ type: String) -> SimpleFileTypeFilter {
        var newSelectedTypes = selectedTypes
        if newSelectedTypes.contains(type) {
            newSelectedTypes.remove(type)
        } else {
            newSelectedTypes.insert(type)
        }
        return SimpleFileTypeFilter(selectedTypes: newSelectedTypes, discoveredTypes: discoveredTypes)
    }
    
    func isSelected(_ type: String) -> Bool {
        selectedTypes.contains(type)
    }
}