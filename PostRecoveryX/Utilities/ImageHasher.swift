import Foundation
import AppKit
import CoreImage
import Accelerate

struct PerceptualHash: Equatable {
    let hash: UInt64
    let rotations: [UInt64] // Hashes for 90°, 180°, 270° rotations
    
    func matches(_ other: PerceptualHash, threshold: Int = 3) -> Bool {
        // Very strict threshold - 3 bits difference maximum (about 5% difference)
        // This should only match nearly identical images or rotations
        
        // Check original
        if hammingDistance(hash, other.hash) <= threshold {
            return true
        }
        
        // Only check rotations against the original (not rotation vs rotation)
        // This prevents false positives from comparing different rotations
        for rotatedHash in rotations {
            if hammingDistance(rotatedHash, other.hash) <= threshold {
                return true
            }
        }
        
        // Check other's rotations against our original
        for otherRotated in other.rotations {
            if hammingDistance(hash, otherRotated) <= threshold {
                return true
            }
        }
        
        return false
    }
    
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        var xor = a ^ b
        var count = 0
        while xor != 0 {
            count += 1
            xor &= xor - 1
        }
        return count
    }
}

class ImageHasher {
    private let context = CIContext()
    
    func computePerceptualHash(for url: URL) async throws -> PerceptualHash? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Compute hash for original and rotations
        let original = try await computeHash(for: ciImage)
        let rotated90 = try await computeHash(for: ciImage.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)))
        let rotated180 = try await computeHash(for: ciImage.transformed(by: CGAffineTransform(rotationAngle: .pi)))
        let rotated270 = try await computeHash(for: ciImage.transformed(by: CGAffineTransform(rotationAngle: .pi * 1.5)))
        
        return PerceptualHash(
            hash: original,
            rotations: [rotated90, rotated180, rotated270]
        )
    }
    
    private func computeHash(for ciImage: CIImage) async throws -> UInt64 {
        // Use 16x16 for better quality hash
        let targetSize: CGFloat = 16
        
        // Calculate aspect-preserving scale
        let scale = min(targetSize / ciImage.extent.width, targetSize / ciImage.extent.height)
        let resized = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Convert to grayscale
        guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
            throw ImageHashError.filterCreationFailed
        }
        grayscaleFilter.setValue(resized, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let grayscale = grayscaleFilter.outputImage else {
            throw ImageHashError.grayscaleConversionFailed
        }
        
        // Get pixel data - using 16x16 for better accuracy
        var pixelData = [Float](repeating: 0, count: 256) // 16x16
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        
        context.render(grayscale, 
                      toBitmap: &pixelData,
                      rowBytes: 16 * MemoryLayout<Float>.size,
                      bounds: rect,
                      format: .RGBAf,
                      colorSpace: CGColorSpaceCreateDeviceGray())
        
        // Compute average directly without DCT for simpler, more reliable hash
        let average = pixelData.reduce(0, +) / Float(pixelData.count)
        
        // Generate hash based on whether each pixel is above or below average
        var hash: UInt64 = 0
        for i in 0..<min(64, pixelData.count) {
            if pixelData[i] > average {
                hash |= (1 << i)
            }
        }
        
        return hash
    }
}

enum ImageHashError: LocalizedError {
    case filterCreationFailed
    case grayscaleConversionFailed
    case renderingFailed
    
    var errorDescription: String? {
        switch self {
        case .filterCreationFailed:
            return "Failed to create image filter"
        case .grayscaleConversionFailed:
            return "Failed to convert image to grayscale"
        case .renderingFailed:
            return "Failed to render image for hashing"
        }
    }
}