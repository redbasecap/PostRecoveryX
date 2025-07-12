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
    
    static let documents = FileTypeCategory(
        name: "Documents",
        systemImage: "doc.text",
        types: [.pdf, .text, .rtf, .plainText],
        extensions: ["pdf", "txt", "rtf", "doc", "docx", "odt", "tex", "md"]
    )
    
    static let spreadsheets = FileTypeCategory(
        name: "Spreadsheets",
        systemImage: "tablecells",
        types: [.spreadsheet],
        extensions: ["xls", "xlsx", "csv", "ods", "numbers"]
    )
    
    static let presentations = FileTypeCategory(
        name: "Presentations",
        systemImage: "play.rectangle",
        types: [.presentation],
        extensions: ["ppt", "pptx", "odp", "key"]
    )
    
    static let archives = FileTypeCategory(
        name: "Archives",
        systemImage: "archivebox",
        types: [.zip, .archive],
        extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso"]
    )
    
    static let audio = FileTypeCategory(
        name: "Audio",
        systemImage: "music.note",
        types: [.audio, .mp3, .mpeg4Audio],
        extensions: ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "ape", "opus"]
    )
    
    static let code = FileTypeCategory(
        name: "Code",
        systemImage: "chevron.left.forwardslash.chevron.right",
        types: [.sourceCode],
        extensions: ["swift", "js", "py", "java", "cpp", "c", "h", "m", "go", "rb", "php", "html", "css", "json", "xml", "yaml", "yml"]
    )
    
    static let data = FileTypeCategory(
        name: "Data Files",
        systemImage: "cylinder.split.1x2",
        types: [.database, .data],
        extensions: ["db", "sqlite", "mdb", "accdb", "dbf", "sql"]
    )
    
    static let allCategories: [FileTypeCategory] = [
        .images, .rawImages, .videos, .documents, .spreadsheets,
        .presentations, .archives, .audio, .code, .data
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