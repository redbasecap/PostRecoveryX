import Foundation
import UniformTypeIdentifiers

struct FileTypeCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let systemImage: String
    let types: Set<UTType>
    let extensions: Set<String>
    
    static let images = FileTypeCategory(
        name: "Images",
        systemImage: "photo",
        types: [.jpeg, .png, .heic, .heif, .tiff, .bmp, .gif, .webP, .svg, .ico, .icns],
        extensions: ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp", "svg", "ico", "icns"]
    )
    
    static let rawImages = FileTypeCategory(
        name: "RAW Images",
        systemImage: "camera.aperture",
        types: [.rawImage],
        extensions: ["cr2", "cr3", "nef", "arw", "orf", "rw2", "dng", "raf", "srw", "crw", "raw"]
    )
    
    static let videos = FileTypeCategory(
        name: "Videos",
        systemImage: "video",
        types: [.mpeg4Movie, .quickTimeMovie, .avi, .mpeg, .mpeg2Video, .movie],
        extensions: ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp"]
    )
    
    static let allCategories: [FileTypeCategory] = [
        .images, .rawImages, .videos
    ]
    
    func matches(fileType: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: "file.\(fileType)").pathExtension.lowercased()
        return extensions.contains(fileExtension) || 
               types.contains { type in
                   UTType(filenameExtension: fileExtension)?.conforms(to: type) ?? false
               }
    }
    
    func matches(contentType: UTType) -> Bool {
        types.contains { type in
            contentType.conforms(to: type)
        }
    }
}

@MainActor
class FileTypeFilter: ObservableObject {
    @Published var enabledCategories: Set<FileTypeCategory> = Set(FileTypeCategory.allCategories)
    @Published var customExtensions: Set<String> = []
    
    var allEnabled: Bool {
        enabledCategories.count == FileTypeCategory.allCategories.count && customExtensions.isEmpty
    }
    
    func toggle(_ category: FileTypeCategory) {
        if enabledCategories.contains(category) {
            enabledCategories.remove(category)
        } else {
            enabledCategories.insert(category)
        }
    }
    
    func enableAll() {
        enabledCategories = Set(FileTypeCategory.allCategories)
        customExtensions.removeAll()
    }
    
    func disableAll() {
        enabledCategories.removeAll()
        customExtensions.removeAll()
    }
    
    func shouldInclude(fileType: String) -> Bool {
        // Check custom extensions first
        let fileExtension = URL(fileURLWithPath: "file.\(fileType)").pathExtension.lowercased()
        if customExtensions.contains(fileExtension) {
            return true
        }
        
        // Check enabled categories
        return enabledCategories.contains { category in
            category.matches(fileType: fileType)
        }
    }
    
    func shouldInclude(contentType: UTType) -> Bool {
        enabledCategories.contains { category in
            category.matches(contentType: contentType)
        }
    }
}