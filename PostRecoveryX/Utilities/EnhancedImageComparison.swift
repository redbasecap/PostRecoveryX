import Foundation
import AppKit
import CoreImage
import Accelerate

struct ColorHistogram {
    let redBins: [Float]
    let greenBins: [Float]
    let blueBins: [Float]
    
    func similarity(to other: ColorHistogram) -> Float {
        // Calculate Bhattacharyya coefficient for histogram similarity
        var redSimilarity: Float = 0
        var greenSimilarity: Float = 0
        var blueSimilarity: Float = 0
        
        for i in 0..<redBins.count {
            redSimilarity += sqrt(redBins[i] * other.redBins[i])
            greenSimilarity += sqrt(greenBins[i] * other.greenBins[i])
            blueSimilarity += sqrt(blueBins[i] * other.blueBins[i])
        }
        
        return (redSimilarity + greenSimilarity + blueSimilarity) / 3.0
    }
}

struct EdgeSignature {
    let horizontalEdges: Float
    let verticalEdges: Float
    let diagonalEdges: Float
    let totalEdgePixels: Int
    
    func similarity(to other: EdgeSignature) -> Float {
        let hDiff = abs(horizontalEdges - other.horizontalEdges)
        let vDiff = abs(verticalEdges - other.verticalEdges)
        let dDiff = abs(diagonalEdges - other.diagonalEdges)
        let totalDiff = abs(Float(totalEdgePixels - other.totalEdgePixels)) / Float(max(totalEdgePixels, other.totalEdgePixels))
        
        // Convert differences to similarity (0-1 range)
        return 1.0 - min((hDiff + vDiff + dDiff + totalDiff) / 4.0, 1.0)
    }
}

struct EnhancedImageHash {
    let perceptualHash: PerceptualHash
    let colorHistogram: ColorHistogram
    let edgeSignature: EdgeSignature
    let dominantColors: [(r: Float, g: Float, b: Float)]
    
    func matches(_ other: EnhancedImageHash, threshold: Float = 0.85) -> (matches: Bool, rotation: Int?, confidence: Float) {
        // First check perceptual hash with very strict threshold
        let (hashMatches, rotation) = perceptualHash.matches(other.perceptualHash, threshold: 2)
        
        if !hashMatches {
            return (false, nil, 0.0)
        }
        
        // If perceptual hash matches, verify with additional metrics
        let colorSimilarity = colorHistogram.similarity(to: other.colorHistogram)
        let edgeSimilarity = edgeSignature.similarity(to: other.edgeSignature)
        let dominantColorSimilarity = compareDominantColors(dominantColors, other.dominantColors)
        
        // Weighted average of all metrics
        let overallSimilarity = (colorSimilarity * 0.4 + edgeSimilarity * 0.3 + dominantColorSimilarity * 0.3)
        
        // Require high similarity across all metrics
        let matches = overallSimilarity >= threshold
        
        return (matches, rotation, overallSimilarity)
    }
    
    private func compareDominantColors(_ colors1: [(r: Float, g: Float, b: Float)], 
                                     _ colors2: [(r: Float, g: Float, b: Float)]) -> Float {
        var totalSimilarity: Float = 0
        let count = min(colors1.count, colors2.count)
        
        guard count > 0 else { return 0 }
        
        for i in 0..<count {
            let c1 = colors1[i]
            let c2 = colors2[i]
            
            // Calculate color distance
            let rDiff = c1.r - c2.r
            let gDiff = c1.g - c2.g
            let bDiff = c1.b - c2.b
            let distance = sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff)
            
            // Convert to similarity (max distance is sqrt(3) for RGB)
            totalSimilarity += 1.0 - (distance / sqrt(3))
        }
        
        return totalSimilarity / Float(count)
    }
}

class EnhancedImageHasher {
    private let context = CIContext()
    private let imageHasher = ImageHasher()
    
    func computeEnhancedHash(for url: URL) async throws -> EnhancedImageHash? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Compute all components in parallel
        async let perceptualHash = imageHasher.computePerceptualHash(for: url)
        async let colorHistogram = computeColorHistogram(for: ciImage)
        async let edgeSignature = computeEdgeSignature(for: ciImage)
        async let dominantColors = extractDominantColors(from: ciImage)
        
        guard let hash = try await perceptualHash,
              let histogram = await colorHistogram,
              let edges = await edgeSignature,
              let colors = await dominantColors else {
            return nil
        }
        
        return EnhancedImageHash(
            perceptualHash: hash,
            colorHistogram: histogram,
            edgeSignature: edges,
            dominantColors: colors
        )
    }
    
    private func computeColorHistogram(for image: CIImage) async -> ColorHistogram? {
        let bins = 16 // 16 bins per channel
        var redBins = [Float](repeating: 0, count: bins)
        var greenBins = [Float](repeating: 0, count: bins)
        var blueBins = [Float](repeating: 0, count: bins)
        
        // Scale image to reasonable size for histogram computation
        let targetSize: CGFloat = 256
        let scale = min(targetSize / image.extent.width, targetSize / image.extent.height)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Get pixel data
        let width = Int(scaledImage.extent.width)
        let height = Int(scaledImage.extent.height)
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        context.render(scaledImage,
                      toBitmap: &pixelData,
                      rowBytes: bytesPerRow,
                      bounds: scaledImage.extent,
                      format: .RGBA8,
                      colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let totalPixels = Float(width * height)
        
        // Build histogram
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                
                let redBin = Int(r) * bins / 256
                let greenBin = Int(g) * bins / 256
                let blueBin = Int(b) * bins / 256
                
                redBins[min(redBin, bins - 1)] += 1
                greenBins[min(greenBin, bins - 1)] += 1
                blueBins[min(blueBin, bins - 1)] += 1
            }
        }
        
        // Normalize
        for i in 0..<bins {
            redBins[i] /= totalPixels
            greenBins[i] /= totalPixels
            blueBins[i] /= totalPixels
        }
        
        return ColorHistogram(redBins: redBins, greenBins: greenBins, blueBins: blueBins)
    }
    
    private func computeEdgeSignature(for image: CIImage) async -> EdgeSignature? {
        // Apply edge detection filter
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(3.0, forKey: kCIInputIntensityKey)
        
        guard let edgeImage = edgeFilter.outputImage else { return nil }
        
        // Scale to manageable size
        let targetSize: CGFloat = 128
        let scale = min(targetSize / edgeImage.extent.width, targetSize / edgeImage.extent.height)
        let scaledImage = edgeImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Analyze edge directions
        let width = Int(scaledImage.extent.width)
        let height = Int(scaledImage.extent.height)
        var pixelData = [Float](repeating: 0, count: width * height)
        
        context.render(scaledImage,
                      toBitmap: &pixelData,
                      rowBytes: width * MemoryLayout<Float>.size,
                      bounds: scaledImage.extent,
                      format: .RGBAf,
                      colorSpace: CGColorSpaceCreateDeviceGray())
        
        var horizontalEdges: Float = 0
        var verticalEdges: Float = 0
        var diagonalEdges: Float = 0
        var totalEdgePixels = 0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = pixelData[y * width + x]
                
                if center > 0.1 { // Edge threshold
                    totalEdgePixels += 1
                    
                    // Check edge direction
                    let left = pixelData[y * width + (x - 1)]
                    let right = pixelData[y * width + (x + 1)]
                    let top = pixelData[(y - 1) * width + x]
                    let bottom = pixelData[(y + 1) * width + x]
                    
                    let horizontalStrength = abs(left - right)
                    let verticalStrength = abs(top - bottom)
                    
                    if horizontalStrength > verticalStrength * 1.5 {
                        horizontalEdges += 1
                    } else if verticalStrength > horizontalStrength * 1.5 {
                        verticalEdges += 1
                    } else {
                        diagonalEdges += 1
                    }
                }
            }
        }
        
        let total = horizontalEdges + verticalEdges + diagonalEdges
        if total > 0 {
            horizontalEdges /= total
            verticalEdges /= total
            diagonalEdges /= total
        }
        
        return EdgeSignature(
            horizontalEdges: horizontalEdges,
            verticalEdges: verticalEdges,
            diagonalEdges: diagonalEdges,
            totalEdgePixels: totalEdgePixels
        )
    }
    
    private func extractDominantColors(from image: CIImage) async -> [(r: Float, g: Float, b: Float)]? {
        // Scale image to small size for color extraction
        let targetSize: CGFloat = 64
        let scale = min(targetSize / image.extent.width, targetSize / image.extent.height)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Get pixel data
        let width = Int(scaledImage.extent.width)
        let height = Int(scaledImage.extent.height)
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        context.render(scaledImage,
                      toBitmap: &pixelData,
                      rowBytes: bytesPerRow,
                      bounds: scaledImage.extent,
                      format: .RGBA8,
                      colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Simple k-means clustering for dominant colors
        var colors: [(r: Float, g: Float, b: Float)] = []
        let k = 3 // Extract 3 dominant colors
        
        // Initialize with random pixels
        for _ in 0..<k {
            let randomPixel = Int.random(in: 0..<(width * height))
            let offset = randomPixel * 4
            colors.append((
                r: Float(pixelData[offset]) / 255.0,
                g: Float(pixelData[offset + 1]) / 255.0,
                b: Float(pixelData[offset + 2]) / 255.0
            ))
        }
        
        // Simple k-means (3 iterations)
        for _ in 0..<3 {
            var clusters = [[Int]](repeating: [], count: k)
            
            // Assign pixels to clusters
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    let pixel = (
                        r: Float(pixelData[offset]) / 255.0,
                        g: Float(pixelData[offset + 1]) / 255.0,
                        b: Float(pixelData[offset + 2]) / 255.0
                    )
                    
                    var minDistance: Float = Float.infinity
                    var closestCluster = 0
                    
                    for (index, center) in colors.enumerated() {
                        let distance = sqrt(
                            pow(pixel.r - center.r, 2) +
                            pow(pixel.g - center.g, 2) +
                            pow(pixel.b - center.b, 2)
                        )
                        
                        if distance < minDistance {
                            minDistance = distance
                            closestCluster = index
                        }
                    }
                    
                    clusters[closestCluster].append(offset)
                }
            }
            
            // Update cluster centers
            for (index, cluster) in clusters.enumerated() {
                if !cluster.isEmpty {
                    var sumR: Float = 0
                    var sumG: Float = 0
                    var sumB: Float = 0
                    
                    for offset in cluster {
                        sumR += Float(pixelData[offset]) / 255.0
                        sumG += Float(pixelData[offset + 1]) / 255.0
                        sumB += Float(pixelData[offset + 2]) / 255.0
                    }
                    
                    let count = Float(cluster.count)
                    colors[index] = (r: sumR / count, g: sumG / count, b: sumB / count)
                }
            }
        }
        
        return colors
    }
}