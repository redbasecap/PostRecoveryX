import Foundation
import CryptoKit
import SwiftData
import UniformTypeIdentifiers

actor DuplicateChecker {
    private var hashCache: [String: String] = [:]
    private var perceptualHashCache: [String: PerceptualHash] = [:]
    private var enhancedHashCache: [String: EnhancedImageHash] = [:]
    private let imageHasher = ImageHasher()
    private let enhancedHasher = EnhancedImageHasher()
    private var isCancelled = false
    private var progress: Progress?
    
    func findDuplicates(in files: [ScannedFile], modelContext: ModelContext, enableVisualMatching: Bool = true) async throws -> [DuplicateGroup] {
        isCancelled = false
        progress = Progress(totalUnitCount: Int64(files.count))
        
        // Start performance monitoring
        await MainActor.run {
            PerformanceMonitor.shared.recordOperationStart("Duplicate Detection")
        }
        
        var hashGroups: [String: [ScannedFile]] = [:]
        var perceptualGroups: [ScannedFile] = []
        
        for file in files {
            if isCancelled {
                throw DuplicateCheckerError.cancelled
            }
            
            do {
                // Record hash computation start
                await MainActor.run {
                    PerformanceMonitor.shared.recordOperationStart("Hash Computation")
                }
                
                let hash = try await computeHash(for: file)
                file.sha256Hash = hash
                file.isProcessed = true
                
                // Record hash computation complete
                await MainActor.run {
                    PerformanceMonitor.shared.recordOperationComplete("Hash Computation")
                    PerformanceMonitor.shared.recordFileProcessed(size: file.fileSize)
                }
                
                // Check if it's an image for enhanced visual matching
                if enableVisualMatching,
                   let uti = UTType(filenameExtension: URL(fileURLWithPath: file.path).pathExtension),
                   uti.conforms(to: .image) {
                    if let enhancedHash = try await computeEnhancedHash(for: file) {
                        file.perceptualHash = enhancedHash.perceptualHash.hash
                        perceptualGroups.append(file)
                    }
                }
                
                if hashGroups[hash] != nil {
                    hashGroups[hash]?.append(file)
                } else {
                    hashGroups[hash] = [file]
                }
                
                progress?.completedUnitCount += 1
            } catch {
                file.error = error.localizedDescription
                file.isProcessed = true
                continue
            }
        }
        
        try modelContext.save()
        
        var duplicateGroups: [DuplicateGroup] = []
        
        // Process exact duplicates
        for (hash, groupFiles) in hashGroups where groupFiles.count > 1 {
            let group = DuplicateGroup(
                sha256Hash: hash,
                fileSize: groupFiles.first?.fileSize ?? 0
            )
            group.files = groupFiles
            group.fileCount = groupFiles.count
            
            for file in groupFiles {
                file.duplicateGroup = group
            }
            
            modelContext.insert(group)
            duplicateGroups.append(group)
        }
        
        // Process visual duplicates with enhanced matching
        if enableVisualMatching && !perceptualGroups.isEmpty {
            let processedPerceptual = NSMutableSet()
            for i in 0..<perceptualGroups.count {
                let file1 = perceptualGroups[i]
                if processedPerceptual.contains(file1.id) || file1.duplicateGroup != nil {
                    continue
                }
                
                guard let hash1 = enhancedHashCache[file1.path] else { continue }
                
                var similarFiles = [file1]
                var matchConfidences: [Float] = [1.0] // First file has 100% match with itself
                
                for j in (i+1)..<perceptualGroups.count {
                    let file2 = perceptualGroups[j]
                    if processedPerceptual.contains(file2.id) || file2.duplicateGroup != nil {
                        continue
                    }
                    
                    guard let hash2 = enhancedHashCache[file2.path] else { continue }
                    
                    let matchResult = hash1.matches(hash2)
                    if matchResult.matches {
                        // Store rotation info relative to the first file
                        if let rotation = matchResult.rotation {
                            file2.suggestedRotation = rotation
                        }
                        similarFiles.append(file2)
                        matchConfidences.append(matchResult.confidence)
                        processedPerceptual.add(file2.id)
                    }
                }
                
                if similarFiles.count > 1 {
                    // Only create group if average confidence is high
                    let avgConfidence = matchConfidences.reduce(0, +) / Float(matchConfidences.count)
                    if avgConfidence > 0.8 {
                        let group = DuplicateGroup(
                            sha256Hash: "visual_\(UUID().uuidString)",
                            fileSize: similarFiles.first?.fileSize ?? 0
                        )
                        group.files = similarFiles
                        group.fileCount = similarFiles.count
                        
                        for file in similarFiles {
                            file.duplicateGroup = group
                        }
                        
                        modelContext.insert(group)
                        duplicateGroups.append(group)
                    }
                }
            }
        }
        
        try modelContext.save()
        
        // Complete performance monitoring
        await MainActor.run {
            PerformanceMonitor.shared.recordOperationComplete("Duplicate Detection")
        }
        
        return duplicateGroups
    }
    
    func computeHash(for file: ScannedFile) async throws -> String {
        if let cachedHash = hashCache[file.path] {
            return cachedHash
        }
        
        let url = URL(fileURLWithPath: file.path)
        
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw DuplicateCheckerError.fileNotFound
        }
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        let bufferSize = 64 * 1024
        
        while true {
            if isCancelled {
                throw DuplicateCheckerError.cancelled
            }
            
            let data = try fileHandle.read(upToCount: bufferSize) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        
        hashCache[file.path] = hash
        return hash
    }
    
    func computePerceptualHash(for file: ScannedFile) async throws -> PerceptualHash? {
        if let cachedHash = perceptualHashCache[file.path] {
            return cachedHash
        }
        
        let url = URL(fileURLWithPath: file.path)
        guard let hash = try await imageHasher.computePerceptualHash(for: url) else {
            return nil
        }
        
        perceptualHashCache[file.path] = hash
        return hash
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func currentProgress() -> Progress? {
        progress
    }
    
    func computeEnhancedHash(for file: ScannedFile) async throws -> EnhancedImageHash? {
        if let cachedHash = enhancedHashCache[file.path] {
            return cachedHash
        }
        
        let url = URL(fileURLWithPath: file.path)
        guard let hash = try await enhancedHasher.computeEnhancedHash(for: url) else {
            return nil
        }
        
        enhancedHashCache[file.path] = hash
        return hash
    }
    
    func clearCache() {
        hashCache.removeAll()
        perceptualHashCache.removeAll()
        enhancedHashCache.removeAll()
    }
}

enum DuplicateCheckerError: LocalizedError {
    case fileNotFound
    case cancelled
    case readError
    case hashingError
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .cancelled:
            return "Duplicate checking was cancelled"
        case .readError:
            return "Error reading file"
        case .hashingError:
            return "Error computing file hash"
        }
    }
}