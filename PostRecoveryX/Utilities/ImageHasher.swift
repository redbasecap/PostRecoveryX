import Foundation
import AppKit
import CoreImage
import Accelerate

/// Legacy perceptual hash structure for backward compatibility
/// New implementations should use GxPerceptualHash from GxImageHasher
struct PerceptualHash: Equatable {
    let hash: UInt64
    let rotations: [UInt64] // Hashes for 90°, 180°, 270° rotations
    
    /// Create from GxPerceptualHash for compatibility
    init(from gxHash: GxPerceptualHash) {
        self.hash = gxHash.original
        self.rotations = [gxHash.rotated90, gxHash.rotated180, gxHash.rotated270]
    }
    
    /// Legacy initializer
    init(hash: UInt64, rotations: [UInt64]) {
        self.hash = hash
        self.rotations = rotations
    }
    
    func matches(_ other: PerceptualHash, threshold: Int = 1) -> (matches: Bool, rotation: Int?) {
        // Extremely strict threshold - 1 bit difference maximum
        // This should only match nearly identical images or rotations
        
        // Check original
        if hammingDistance(hash, other.hash) <= threshold {
            return (true, nil) // No rotation needed
        }
        
        // Check our rotations against other's original
        for (index, rotatedHash) in rotations.enumerated() {
            if hammingDistance(rotatedHash, other.hash) <= threshold {
                // This image needs to be rotated by (index + 1) * 90 degrees
                return (true, (index + 1) * 90)
            }
        }
        
        // Check other's rotations against our original
        for (index, otherRotated) in other.rotations.enumerated() {
            if hammingDistance(hash, otherRotated) <= threshold {
                // The other image is rotated, so we need negative rotation
                return (true, -(index + 1) * 90)
            }
        }
        
        return (false, nil)
    }
    
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount // Use optimized bit count
    }
}

/// Legacy ImageHasher - use GxImageHasher for new implementations
class ImageHasher {
    private let gxHasher = GxImageHasher()
    
    func computePerceptualHash(for url: URL) async throws -> PerceptualHash? {
        // Use GxImageHasher for better performance
        guard let gxHash = try await gxHasher.computeHash(for: url) else {
            return nil
        }
        
        // Convert to legacy format for compatibility
        return PerceptualHash(from: gxHash)
    }
    
    /// Batch compute hashes for multiple URLs - delegates to GxImageHasher
    func computeBatch(urls: [URL]) async throws -> [URL: PerceptualHash] {
        let gxResults = try await gxHasher.computeBatch(urls: urls)
        
        // Convert results to legacy format
        var results = [URL: PerceptualHash]()
        for (url, gxHash) in gxResults {
            results[url] = PerceptualHash(from: gxHash)
        }
        return results
    }
}

// ImageHashError is now defined in GxImageHasher.swift