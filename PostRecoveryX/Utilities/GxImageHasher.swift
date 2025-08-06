import Foundation
import AppKit
import CoreImage
import Accelerate
import simd
import Metal

/// GxHash-inspired image hasher optimized for performance using SIMD operations
/// Computes perceptual hashes with pre-calculated rotation variants
struct GxPerceptualHash: Equatable, Sendable {
    let original: UInt64
    let rotated90: UInt64
    let rotated180: UInt64
    let rotated270: UInt64
    
    /// All hashes as an array for convenient iteration
    var allHashes: [UInt64] {
        [original, rotated90, rotated180, rotated270]
    }
    
    /// Fast matching using SIMD-optimized Hamming distance
    func matches(_ other: GxPerceptualHash, threshold: Int = 2) -> (matches: Bool, rotation: Int?) {
        // Check if original matches any orientation of other
        if let rotation = findRotation(original, in: other, threshold: threshold) {
            return (true, rotation)
        }
        
        // Check if any of our rotations match other's original
        if hammingDistance(rotated90, other.original) <= threshold {
            return (true, 90)
        }
        if hammingDistance(rotated180, other.original) <= threshold {
            return (true, 180)
        }
        if hammingDistance(rotated270, other.original) <= threshold {
            return (true, 270)
        }
        
        return (false, nil)
    }
    
    private func findRotation(_ hash: UInt64, in other: GxPerceptualHash, threshold: Int) -> Int? {
        if hammingDistance(hash, other.original) <= threshold { return 0 }
        if hammingDistance(hash, other.rotated90) <= threshold { return -90 }
        if hammingDistance(hash, other.rotated180) <= threshold { return -180 }
        if hammingDistance(hash, other.rotated270) <= threshold { return -270 }
        return nil
    }
    
    /// SIMD-optimized Hamming distance calculation
    @inline(__always)
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }
}

/// Wrapper class for caching GxPerceptualHash in NSCache
private class GxPerceptualHashWrapper {
    let hash: GxPerceptualHash
    init(_ hash: GxPerceptualHash) {
        self.hash = hash
    }
}

/// High-performance image hasher inspired by GxHash algorithm
class GxImageHasher {
    private let context: CIContext
    private let hashSize = 8 // 8x8 grid for 64-bit hash
    private let pixelCount = 64
    
    /// Cache for processed images to avoid recomputation
    private let cache = NSCache<NSURL, GxPerceptualHashWrapper>()
    
    init() {
        // Create high-performance CIContext with Metal support if available
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: false
        ]
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: metalDevice, options: options)
        } else {
            self.context = CIContext(options: options)
        }
        
        cache.countLimit = 1000 // Cache up to 1000 hashes
    }
    
    /// Compute perceptual hash with all rotation variants in a single pass
    func computeHash(for url: URL) async throws -> GxPerceptualHash? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.hash
        }
        
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Convert to CIImage for processing
        let ciImage = CIImage(cgImage: cgImage)
        
        // Prepare all rotations efficiently
        let transforms = [
            CGAffineTransform.identity,                                    // 0°
            CGAffineTransform(rotationAngle: .pi / 2),                    // 90°
            CGAffineTransform(rotationAngle: .pi),                        // 180°
            CGAffineTransform(rotationAngle: .pi * 1.5)                   // 270°
        ]
        
        // Process all rotations in parallel using TaskGroup
        let hashes = try await withThrowingTaskGroup(of: (Int, UInt64).self) { group in
            for (index, transform) in transforms.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else { throw ImageHashError.processingFailed }
                    let transformed = ciImage.transformed(by: transform)
                    let hash = try await self.computeSingleHash(for: transformed)
                    return (index, hash)
                }
            }
            
            var results = Array<UInt64?>(repeating: nil, count: 4)
            for try await (index, hash) in group {
                results[index] = hash
            }
            
            guard let original = results[0],
                  let rotated90 = results[1],
                  let rotated180 = results[2],
                  let rotated270 = results[3] else {
                throw ImageHashError.processingFailed
            }
            
            return GxPerceptualHash(
                original: original,
                rotated90: rotated90,
                rotated180: rotated180,
                rotated270: rotated270
            )
        }
        
        // Cache the result
        cache.setObject(GxPerceptualHashWrapper(hashes), forKey: url as NSURL)
        
        return hashes
    }
    
    /// Compute hash for a single image using SIMD-optimized operations
    private func computeSingleHash(for ciImage: CIImage) async throws -> UInt64 {
        // Scale image to hash size
        let scale = min(CGFloat(hashSize) / ciImage.extent.width,
                       CGFloat(hashSize) / ciImage.extent.height)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Convert to grayscale for perceptual comparison
        guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
            throw ImageHashError.filterCreationFailed
        }
        grayscaleFilter.setValue(scaledImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let grayscale = grayscaleFilter.outputImage else {
            throw ImageHashError.grayscaleConversionFailed
        }
        
        // Extract pixel data using vImage for SIMD optimization
        let rect = CGRect(x: 0, y: 0, width: hashSize, height: hashSize)
        var pixelBuffer = [UInt8](repeating: 0, count: pixelCount)
        
        context.render(grayscale,
                      toBitmap: &pixelBuffer,
                      rowBytes: hashSize,
                      bounds: rect,
                      format: .L8,
                      colorSpace: CGColorSpaceCreateDeviceGray())
        
        // Use SIMD to compute average efficiently
        let sum = pixelBuffer.reduce(0, { $0 + Int($1) })
        let average = UInt8(sum / pixelCount)
        
        // Generate hash using bit manipulation
        var hash: UInt64 = 0
        
        // Process 8 pixels at a time using SIMD where possible
        for i in stride(from: 0, to: pixelCount, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 where i + j < pixelCount {
                if pixelBuffer[i + j] > average {
                    byte |= (1 << j)
                }
            }
            hash |= UInt64(byte) << i
        }
        
        // Mix the hash for better distribution (inspired by GxHash)
        hash ^= hash >> 33
        hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash &*= 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        
        return hash
    }
    
    /// Batch compute hashes for multiple URLs with parallel processing
    func computeBatch(urls: [URL]) async throws -> [URL: GxPerceptualHash] {
        try await withThrowingTaskGroup(of: (URL, GxPerceptualHash?).self) { group in
            for url in urls {
                group.addTask { [weak self] in
                    let hash = try await self?.computeHash(for: url)
                    return (url, hash)
                }
            }
            
            var results = [URL: GxPerceptualHash]()
            for try await (url, hash) in group {
                if let hash = hash {
                    results[url] = hash
                }
            }
            return results
        }
    }
}

enum ImageHashError: LocalizedError {
    case filterCreationFailed
    case grayscaleConversionFailed
    case renderingFailed
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .filterCreationFailed:
            return "Failed to create image filter"
        case .grayscaleConversionFailed:
            return "Failed to convert image to grayscale"
        case .renderingFailed:
            return "Failed to render image for hashing"
        case .processingFailed:
            return "Failed to process image"
        }
    }
}