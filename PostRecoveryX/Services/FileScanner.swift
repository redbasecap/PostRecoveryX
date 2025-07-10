import Foundation
import UniformTypeIdentifiers
import SwiftData

actor FileScanner {
    private let supportedImageTypes: Set<UTType> = [
        .jpeg, .png, .heic, .heif, .tiff, .bmp, .gif, .webP,
        .rawImage, .svg, .ico, .icns
    ]
    
    private let supportedVideoTypes: Set<UTType> = [
        .mpeg4Movie, .quickTimeMovie, .avi, .mpeg, .mpeg2Video
    ]
    
    private var isCancelled = false
    private var progress: Progress?
    
    func scanDirectory(at url: URL, includeVideos: Bool = false) async throws -> [URL] {
        isCancelled = false
        var discoveredFiles: [URL] = []
        
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentTypeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileScannerError.cannotCreateEnumerator
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if isCancelled {
                throw FileScannerError.cancelled
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                guard let isRegularFile = resourceValues.isRegularFile,
                      isRegularFile,
                      let contentType = resourceValues.contentType else {
                    continue
                }
                
                if isSupported(contentType: contentType, includeVideos: includeVideos) {
                    discoveredFiles.append(fileURL)
                }
            } catch {
                continue
            }
        }
        
        return discoveredFiles
    }
    
    func createScannedFiles(from urls: [URL], in modelContext: ModelContext) async throws -> [ScannedFile] {
        var scannedFiles: [ScannedFile] = []
        
        progress = Progress(totalUnitCount: Int64(urls.count))
        
        for url in urls {
            if isCancelled {
                throw FileScannerError.cancelled
            }
            
            do {
                let resourceValues = try url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .contentTypeKey,
                    .creationDateKey,
                    .contentModificationDateKey
                ])
                
                let fileSize = Int64(resourceValues.fileSize ?? 0)
                let scannedFile = ScannedFile(
                    path: url.path,
                    fileName: url.lastPathComponent,
                    fileSize: fileSize,
                    fileType: resourceValues.contentType?.identifier ?? "unknown"
                )
                
                scannedFile.creationDate = resourceValues.creationDate
                scannedFile.modificationDate = resourceValues.contentModificationDate
                
                // Mark as thumbnail if it matches thumbnail criteria
                scannedFile.isThumbnail = scannedFile.isPotentialThumbnail
                
                modelContext.insert(scannedFile)
                scannedFiles.append(scannedFile)
                
                progress?.completedUnitCount += 1
            } catch {
                continue
            }
        }
        
        try modelContext.save()
        return scannedFiles
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func currentProgress() -> Progress? {
        progress
    }
    
    private func isSupported(contentType: UTType, includeVideos: Bool) -> Bool {
        for imageType in supportedImageTypes {
            if contentType.conforms(to: imageType) {
                return true
            }
        }
        
        if includeVideos {
            for videoType in supportedVideoTypes {
                if contentType.conforms(to: videoType) {
                    return true
                }
            }
        }
        
        return false
    }
}

enum FileScannerError: LocalizedError {
    case cannotCreateEnumerator
    case cancelled
    case invalidDirectory
    
    var errorDescription: String? {
        switch self {
        case .cannotCreateEnumerator:
            return "Cannot access the selected directory"
        case .cancelled:
            return "Scan was cancelled"
        case .invalidDirectory:
            return "The selected path is not a valid directory"
        }
    }
}