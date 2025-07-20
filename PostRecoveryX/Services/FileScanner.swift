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
        
        // Collect all URLs first for batch processing
        var allURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if isCancelled {
                throw FileScannerError.cancelled
            }
            allURLs.append(fileURL)
        }
        
        // Process URLs in concurrent batches for better performance
        let batchSize = PerformanceConfiguration.shared.fileScanningBatchSize
        let batches = allURLs.chunked(into: batchSize)
        
        for batch in batches {
            if isCancelled {
                throw FileScannerError.cancelled
            }
            
            let batchResults = await withTaskGroup(of: [(URL, Bool, Int)].self) { group in
                group.addTask {
                    var results: [(URL, Bool, Int)] = []
                    
                    for fileURL in batch {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                            
                            guard let isRegularFile = resourceValues.isRegularFile,
                                  isRegularFile else {
                                continue
                            }
                            
                            let fileSize = resourceValues.fileSize ?? 0
                            var shouldIncludeFile = false
                            
                            // Include all regular files when scanning all types
                            if scanAllTypes {
                                shouldIncludeFile = true
                            } else if let contentType = resourceValues.contentType,
                                     self.isImageOrVideo(contentType: contentType) {
                                // Legacy mode: only images and videos
                                shouldIncludeFile = true
                            }
                            
                            if shouldIncludeFile {
                                results.append((fileURL, true, fileSize))
                            }
                        } catch {
                            continue
                        }
                    }
                    
                    return results
                }
                
                var allBatchResults: [(URL, Bool, Int)] = []
                for await batchResult in group {
                    allBatchResults.append(contentsOf: batchResult)
                }
                return allBatchResults
            }
            
            // Add valid files to discovered files and report progress
            for (fileURL, shouldInclude, fileSize) in batchResults {
                if shouldInclude {
                    discoveredFiles.append(fileURL)
                    
                    // Record file processed for performance monitoring
                    await MainActor.run {
                        PerformanceMonitor.shared.recordFileProcessed(size: Int64(fileSize))
                    }
                }
            }
            
            // Report progress for the batch
            if let callback = progressCallback, let lastFile = batchResults.last {
                let currentCount = discoveredFiles.count
                let fileName = lastFile.0.lastPathComponent
                await MainActor.run {
                    callback(fileName, currentCount)
                }
            }
        }
        
        // Complete operation tracking
        await MainActor.run {
            PerformanceMonitor.shared.recordOperationComplete("File Discovery")
        }
        
        return discoveredFiles
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