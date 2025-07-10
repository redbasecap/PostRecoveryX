import Foundation
import AppKit
import CoreImage
import Accelerate

struct PerceptualHash: Equatable {
    let hash: UInt64
    let rotations: [UInt64] // Hashes for 90°, 180°, 270° rotations
    
    func matches(_ other: PerceptualHash, threshold: Int = 10) -> Bool {
        // Check original
        if hammingDistance(hash, other.hash) <= threshold {
            return true
        }
        
        // Check against all rotations
        for rotatedHash in rotations {
            if hammingDistance(rotatedHash, other.hash) <= threshold {
                return true
            }
            for otherRotated in other.rotations {
                if hammingDistance(rotatedHash, otherRotated) <= threshold {
                    return true
                }
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
        // Resize to 9x8 for DCT
        let resized = ciImage.transformed(by: CGAffineTransform(scaleX: 9.0 / ciImage.extent.width, y: 8.0 / ciImage.extent.height))
        
        // Convert to grayscale
        guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
            throw ImageHashError.filterCreationFailed
        }
        grayscaleFilter.setValue(resized, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let grayscale = grayscaleFilter.outputImage else {
            throw ImageHashError.grayscaleConversionFailed
        }
        
        // Get pixel data
        var pixelData = [Float](repeating: 0, count: 72) // 9x8
        let rect = CGRect(x: 0, y: 0, width: 9, height: 8)
        
        context.render(grayscale, 
                      toBitmap: &pixelData,
                      rowBytes: 9 * MemoryLayout<Float>.size,
                      bounds: rect,
                      format: .RGBAf,
                      colorSpace: CGColorSpaceCreateDeviceGray())
        
        // Compute DCT
        let dctValues = computeDCT(pixelData, width: 9, height: 8)
        
        // Extract top-left 8x8 (excluding DC component)
        var sum: Float = 0
        var values: [Float] = []
        
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue } // Skip DC component
                let index = y * 9 + x
                values.append(dctValues[index])
                sum += dctValues[index]
            }
        }
        
        let average = sum / Float(values.count)
        
        // Generate hash
        var hash: UInt64 = 0
        for (i, value) in values.enumerated() where i < 64 {
            if value > average {
                hash |= (1 << i)
            }
        }
        
        return hash
    }
    
    private func computeDCT(_ input: [Float], width: Int, height: Int) -> [Float] {
        var output = [Float](repeating: 0, count: width * height)
        
        let piOverWidth = Float.pi / Float(width)
        let piOverHeight = Float.pi / Float(height)
        
        for u in 0..<width {
            for v in 0..<height {
                var sum: Float = 0
                
                for x in 0..<width {
                    for y in 0..<height {
                        let pixel = input[y * width + x]
                        let cosX = cos(piOverWidth * (Float(x) + 0.5) * Float(u))
                        let cosY = cos(piOverHeight * (Float(y) + 0.5) * Float(v))
                        sum += pixel * cosX * cosY
                    }
                }
                
                let cu = u == 0 ? 1.0 / sqrt(2.0) : 1.0
                let cv = v == 0 ? 1.0 / sqrt(2.0) : 1.0
                output[v * width + u] = sum * cu * cv * 2.0 / sqrt(Float(width * height))
            }
        }
        
        return output
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