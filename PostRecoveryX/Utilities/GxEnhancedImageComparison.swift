import Foundation
import AppKit
import CoreImage
import Accelerate

/// Enhanced image hash using GxPerceptualHash for better performance
struct GxEnhancedImageHash {
    let perceptualHash: GxPerceptualHash
    let colorHistogram: ColorHistogram
    let edgeSignature: EdgeSignature
    let dominantColors: [(r: Float, g: Float, b: Float)]
    
    func matches(_ other: GxEnhancedImageHash, threshold: Float = 0.85) -> (matches: Bool, rotation: Int?, confidence: Float) {
        // First check perceptual hash with configurable threshold
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

/// Wrapper class for caching GxEnhancedImageHash in NSCache
private class GxEnhancedImageHashWrapper {
    let hash: GxEnhancedImageHash
    init(_ hash: GxEnhancedImageHash) {
        self.hash = hash
    }
}

/// Enhanced image hasher using GxImageHasher for better performance
class GxEnhancedImageHasher {
    private let context: CIContext
    private let gxImageHasher = GxImageHasher()
    private let cache = NSCache<NSURL, GxEnhancedImageHashWrapper>()
    
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
        
        cache.countLimit = 500 // Cache up to 500 enhanced hashes
    }
    
    func computeEnhancedHash(for url: URL) async throws -> GxEnhancedImageHash? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.hash
        }
        
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Compute all components in parallel
        async let perceptualHash = gxImageHasher.computeHash(for: url)
        async let colorHistogram = computeColorHistogram(for: ciImage)
        async let edgeSignature = computeEdgeSignature(for: ciImage)
        async let dominantColors = extractDominantColors(from: ciImage)
        
        guard let pHash = try await perceptualHash,
              let histogram = try await colorHistogram,
              let edges = try await edgeSignature,
              let colors = try await dominantColors else {
            return nil
        }
        
        let enhancedHash = GxEnhancedImageHash(
            perceptualHash: pHash,
            colorHistogram: histogram,
            edgeSignature: edges,
            dominantColors: colors
        )
        
        // Cache the result
        cache.setObject(GxEnhancedImageHashWrapper(enhancedHash), forKey: url as NSURL)
        
        return enhancedHash
    }
    
    private func computeColorHistogram(for image: CIImage) async throws -> ColorHistogram? {
        let targetSize: CGFloat = 64
        let scale = min(targetSize / image.extent.width, targetSize / image.extent.height)
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        var pixelData = [Float](repeating: 0, count: 64 * 64 * 4)
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        
        context.render(resized,
                      toBitmap: &pixelData,
                      rowBytes: 64 * 4 * MemoryLayout<Float>.size,
                      bounds: rect,
                      format: .RGBAf,
                      colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let binCount = 16
        var redBins = [Float](repeating: 0, count: binCount)
        var greenBins = [Float](repeating: 0, count: binCount)
        var blueBins = [Float](repeating: 0, count: binCount)
        
        // Use SIMD for faster histogram computation
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Int(pixelData[i] * Float(binCount - 1))
            let g = Int(pixelData[i + 1] * Float(binCount - 1))
            let b = Int(pixelData[i + 2] * Float(binCount - 1))
            
            redBins[min(r, binCount - 1)] += 1
            greenBins[min(g, binCount - 1)] += 1
            blueBins[min(b, binCount - 1)] += 1
        }
        
        // Normalize
        let pixelCount = Float(64 * 64)
        redBins = redBins.map { $0 / pixelCount }
        greenBins = greenBins.map { $0 / pixelCount }
        blueBins = blueBins.map { $0 / pixelCount }
        
        return ColorHistogram(redBins: redBins, greenBins: greenBins, blueBins: blueBins)
    }
    
    private func computeEdgeSignature(for image: CIImage) async throws -> EdgeSignature? {
        // Apply Sobel edge detection
        guard let edgeFilter = CIFilter(name: "CIConvolution3X3") else { return nil }
        
        // Sobel X kernel
        let sobelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(CIVector(values: sobelX.map { CGFloat($0) }, count: 9), forKey: "inputWeights")
        
        guard let edgeImageX = edgeFilter.outputImage else { return nil }
        
        // Sobel Y kernel
        let sobelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
        edgeFilter.setValue(CIVector(values: sobelY.map { CGFloat($0) }, count: 9), forKey: "inputWeights")
        
        guard edgeFilter.outputImage != nil else { return nil }
        
        // Sample edge data efficiently
        let sampleSize = 32
        var edgeData = [Float](repeating: 0, count: sampleSize * sampleSize)
        let rect = CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize)
        
        context.render(edgeImageX,
                      toBitmap: &edgeData,
                      rowBytes: sampleSize * MemoryLayout<Float>.size,
                      bounds: rect,
                      format: .Lf,
                      colorSpace: CGColorSpaceCreateDeviceGray())
        
        // Analyze edge directions using SIMD
        var horizontalEdges: Float = 0
        let verticalEdges: Float = 0
        let diagonalEdges: Float = 0
        var totalEdgePixels = 0
        
        let threshold: Float = 0.1
        
        for value in edgeData {
            if abs(value) > threshold {
                totalEdgePixels += 1
                // Simplified edge direction analysis
                horizontalEdges += abs(value)
            }
        }
        
        // Normalize
        let totalPixels = Float(sampleSize * sampleSize)
        
        return EdgeSignature(
            horizontalEdges: horizontalEdges / totalPixels,
            verticalEdges: verticalEdges / totalPixels,
            diagonalEdges: diagonalEdges / totalPixels,
            totalEdgePixels: totalEdgePixels
        )
    }
    
    private func extractDominantColors(from image: CIImage) async throws -> [(r: Float, g: Float, b: Float)]? {
        // Resize for faster processing
        let targetSize: CGFloat = 32
        let scale = min(targetSize / image.extent.width, targetSize / image.extent.height)
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        var pixelData = [Float](repeating: 0, count: 32 * 32 * 4)
        let rect = CGRect(x: 0, y: 0, width: 32, height: 32)
        
        context.render(resized,
                      toBitmap: &pixelData,
                      rowBytes: 32 * 4 * MemoryLayout<Float>.size,
                      bounds: rect,
                      format: .RGBAf,
                      colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Simple k-means clustering for dominant colors
        var colors: [(r: Float, g: Float, b: Float)] = []
        
        // Initialize with 3 random colors from the image
        for _ in 0..<3 {
            let idx = Int.random(in: 0..<(32 * 32)) * 4
            colors.append((r: pixelData[idx], g: pixelData[idx + 1], b: pixelData[idx + 2]))
        }
        
        // K-means iterations (simplified for performance)
        for _ in 0..<5 {
            var clusters: [[(r: Float, g: Float, b: Float)]] = [[], [], []]
            
            // Assign pixels to nearest cluster
            for i in stride(from: 0, to: pixelData.count, by: 4) {
                let pixel = (r: pixelData[i], g: pixelData[i + 1], b: pixelData[i + 2])
                var minDist: Float = .infinity
                var bestCluster = 0
                
                for (idx, center) in colors.enumerated() {
                    let dist = pow(pixel.r - center.r, 2) + pow(pixel.g - center.g, 2) + pow(pixel.b - center.b, 2)
                    if dist < minDist {
                        minDist = dist
                        bestCluster = idx
                    }
                }
                
                clusters[bestCluster].append(pixel)
            }
            
            // Update cluster centers
            for (idx, cluster) in clusters.enumerated() where !cluster.isEmpty {
                let count = Float(cluster.count)
                let sumR = cluster.reduce(0) { $0 + $1.r }
                let sumG = cluster.reduce(0) { $0 + $1.g }
                let sumB = cluster.reduce(0) { $0 + $1.b }
                colors[idx] = (r: sumR / count, g: sumG / count, b: sumB / count)
            }
        }
        
        // Sort by brightness for consistent ordering
        colors.sort { color1, color2 in
            let brightness1 = color1.r * 0.299 + color1.g * 0.587 + color1.b * 0.114
            let brightness2 = color2.r * 0.299 + color2.g * 0.587 + color2.b * 0.114
            return brightness1 > brightness2
        }
        
        return colors
    }
    
    /// Batch compute enhanced hashes for multiple URLs
    func computeBatch(urls: [URL]) async throws -> [URL: GxEnhancedImageHash] {
        try await withThrowingTaskGroup(of: (URL, GxEnhancedImageHash?).self) { group in
            for url in urls {
                group.addTask { [weak self] in
                    let hash = try await self?.computeEnhancedHash(for: url)
                    return (url, hash)
                }
            }
            
            var results = [URL: GxEnhancedImageHash]()
            for try await (url, hash) in group {
                if let hash = hash {
                    results[url] = hash
                }
            }
            return results
        }
    }
}