import Foundation
import UniformTypeIdentifiers

actor FileScanner {
    private var isCancelled = false
    private var progress: Progress?
    
    // Progress callback
    typealias ProgressCallback = (String, Int) -> Void
    
    // Scan ALL files, filtering will be done later
    func scanDirectory(at url: URL, scanAllTypes: Bool = true, progressCallback: ProgressCallback? = nil) async throws -> [URL] {
        isCancelled = false
        var discoveredFiles: [URL] = []
        
        // Start performance monitoring for scanning phase
        await MainActor.run {
            PerformanceMonitor.shared.recordOperationStart("File Discovery")
        }
        
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
                      isRegularFile else {
                    continue
                }
                
                let fileSize = resourceValues.fileSize ?? 0
                
                // Include all regular files when scanning all types
                if scanAllTypes {
                    discoveredFiles.append(fileURL)
                    // Record file processed for performance monitoring
                    await MainActor.run {
                        PerformanceMonitor.shared.recordFileProcessed(size: Int64(fileSize))
                    }
                } else if let contentType = resourceValues.contentType,
                         isImageOrVideo(contentType: contentType) {
                    // Legacy mode: only images and videos
                    discoveredFiles.append(fileURL)
                    await MainActor.run {
                        PerformanceMonitor.shared.recordFileProcessed(size: Int64(fileSize))
                    }
                }
                
                // Report progress
                if let callback = progressCallback {
                    await MainActor.run {
                        callback(fileURL.lastPathComponent, discoveredFiles.count)
                    }
                }
            } catch {
                continue
            }
        }
        
        // Complete operation tracking
        await MainActor.run {
            PerformanceMonitor.shared.recordOperationComplete("File Discovery")
        }
        
        return discoveredFiles
    }
    
    func createScannedFiles(from urls: [URL]) async throws -> [ScannedFile] {
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
                
                scannedFiles.append(scannedFile)
                
                progress?.completedUnitCount += 1
            } catch {
                continue
            }
        }
        
        return scannedFiles
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func currentProgress() -> Progress? {
        progress
    }
    
    private func isImageOrVideo(contentType: UTType) -> Bool {
        // Check if it's an image
        let imageTypes: [UTType] = [
            .jpeg, .png, .heic, .heif, .tiff, .bmp, .gif, .webP,
            .rawImage, .svg, .ico, .icns
        ]
        
        for imageType in imageTypes {
            if contentType.conforms(to: imageType) {
                return true
            }
        }
        
        // Check if it's a video
        let videoTypes: [UTType] = [
            .mpeg4Movie, .quickTimeMovie, .avi, .mpeg, .mpeg2Video
        ]
        
        for videoType in videoTypes {
            if contentType.conforms(to: videoType) {
                return true
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