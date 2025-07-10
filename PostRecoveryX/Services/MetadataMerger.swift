import Foundation
import SwiftData

class MetadataMerger {
    
    struct MergeRecommendation {
        let sourceFile: ScannedFile
        let targetFile: ScannedFile
        let recommendations: [MetadataRecommendation]
        let mergedMetadata: MergedMetadata
    }
    
    struct MetadataRecommendation {
        let field: String
        let sourceValue: Any?
        let targetValue: Any?
        let recommendedValue: Any?
        let reason: String
    }
    
    struct MergedMetadata {
        var originalCreationDate: Date?
        var cameraModel: String?
        var width: Int?
        var height: Int?
        var bestFileName: String
        var hasCompleteMetadata: Bool
    }
    
    func recommendMerge(for group: DuplicateGroup) -> MergeRecommendation? {
        guard group.files.count >= 2 else { return nil }
        
        // Find file with most complete metadata
        let filesWithMetadata = group.files.sorted { file1, file2 in
            metadataCompleteness(of: file1) > metadataCompleteness(of: file2)
        }
        
        guard let primaryFile = filesWithMetadata.first,
              let secondaryFile = filesWithMetadata.dropFirst().first else { return nil }
        
        var recommendations: [MetadataRecommendation] = []
        var mergedMetadata = MergedMetadata(
            bestFileName: primaryFile.fileName,
            hasCompleteMetadata: false
        )
        
        // Analyze creation date
        let dateRec = analyzeCreationDate(primary: primaryFile, secondary: secondaryFile)
        recommendations.append(dateRec)
        mergedMetadata.originalCreationDate = dateRec.recommendedValue as? Date
        
        // Analyze camera model
        let cameraRec = analyzeCameraModel(primary: primaryFile, secondary: secondaryFile)
        recommendations.append(cameraRec)
        mergedMetadata.cameraModel = cameraRec.recommendedValue as? String
        
        // Analyze dimensions (important for rotated images)
        let dimensionRec = analyzeDimensions(primary: primaryFile, secondary: secondaryFile)
        recommendations.append(dimensionRec)
        if let dims = dimensionRec.recommendedValue as? (Int, Int) {
            mergedMetadata.width = dims.0
            mergedMetadata.height = dims.1
        }
        
        // Analyze file names
        let nameRec = analyzeFileName(primary: primaryFile, secondary: secondaryFile, group: group)
        recommendations.append(nameRec)
        mergedMetadata.bestFileName = (nameRec.recommendedValue as? String) ?? primaryFile.fileName
        
        // Check if we have complete metadata
        mergedMetadata.hasCompleteMetadata = mergedMetadata.originalCreationDate != nil &&
                                            mergedMetadata.cameraModel != nil &&
                                            mergedMetadata.width != nil &&
                                            mergedMetadata.height != nil
        
        return MergeRecommendation(
            sourceFile: secondaryFile,
            targetFile: primaryFile,
            recommendations: recommendations,
            mergedMetadata: mergedMetadata
        )
    }
    
    private func metadataCompleteness(of file: ScannedFile) -> Int {
        var score = 0
        if file.originalCreationDate != nil { score += 3 }
        if file.creationDate != nil { score += 1 }
        if file.cameraModel != nil { score += 2 }
        if file.width != nil && file.height != nil { score += 2 }
        if file.hasMetadata { score += 2 }
        return score
    }
    
    private func analyzeCreationDate(primary: ScannedFile, secondary: ScannedFile) -> MetadataRecommendation {
        let primaryDate = primary.originalCreationDate ?? primary.creationDate
        let secondaryDate = secondary.originalCreationDate ?? secondary.creationDate
        
        if let pDate = primaryDate, let sDate = secondaryDate {
            // Choose the earlier date (likely the original)
            let recommended = pDate < sDate ? pDate : sDate
            let reason = pDate < sDate ? "Using earlier date from primary file (likely original)" : "Using earlier date from secondary file (likely original)"
            
            return MetadataRecommendation(
                field: "Creation Date",
                sourceValue: secondaryDate,
                targetValue: primaryDate,
                recommendedValue: recommended,
                reason: reason
            )
        } else if let date = primaryDate ?? secondaryDate {
            return MetadataRecommendation(
                field: "Creation Date",
                sourceValue: secondaryDate,
                targetValue: primaryDate,
                recommendedValue: date,
                reason: "Using the only available date"
            )
        } else {
            return MetadataRecommendation(
                field: "Creation Date",
                sourceValue: nil,
                targetValue: nil,
                recommendedValue: nil,
                reason: "No date metadata available in either file"
            )
        }
    }
    
    private func analyzeCameraModel(primary: ScannedFile, secondary: ScannedFile) -> MetadataRecommendation {
        if let pCamera = primary.cameraModel, let sCamera = secondary.cameraModel {
            // If different, prefer the more detailed one
            let recommended = pCamera.count > sCamera.count ? pCamera : sCamera
            let reason = pCamera == sCamera ? "Same camera model in both files" : "Using more detailed camera information"
            
            return MetadataRecommendation(
                field: "Camera Model",
                sourceValue: sCamera,
                targetValue: pCamera,
                recommendedValue: recommended,
                reason: reason
            )
        } else if let camera = primary.cameraModel ?? secondary.cameraModel {
            return MetadataRecommendation(
                field: "Camera Model",
                sourceValue: secondary.cameraModel,
                targetValue: primary.cameraModel,
                recommendedValue: camera,
                reason: "Using the only available camera model"
            )
        } else {
            return MetadataRecommendation(
                field: "Camera Model",
                sourceValue: nil,
                targetValue: nil,
                recommendedValue: nil,
                reason: "No camera metadata available"
            )
        }
    }
    
    private func analyzeDimensions(primary: ScannedFile, secondary: ScannedFile) -> MetadataRecommendation {
        let pDims = (primary.width, primary.height)
        let sDims = (secondary.width, secondary.height)
        
        if let pw = pDims.0, let ph = pDims.1, let sw = sDims.0, let sh = sDims.1 {
            // Check if one is rotated version of the other
            let isRotated = (pw == sh && ph == sw)
            
            if isRotated {
                // Keep the landscape orientation as standard
                let recommended = pw > ph ? (pw, ph) : (sw, sh)
                return MetadataRecommendation(
                    field: "Dimensions",
                    sourceValue: "\(sw) × \(sh)",
                    targetValue: "\(pw) × \(ph)",
                    recommendedValue: recommended,
                    reason: "Images are rotated versions - standardizing to landscape orientation"
                )
            } else {
                // Use higher resolution
                let pPixels = pw * ph
                let sPixels = sw * sh
                let recommended = pPixels >= sPixels ? (pw, ph) : (sw, sh)
                
                return MetadataRecommendation(
                    field: "Dimensions",
                    sourceValue: "\(sw) × \(sh)",
                    targetValue: "\(pw) × \(ph)",
                    recommendedValue: recommended,
                    reason: "Using higher resolution version"
                )
            }
        } else if let w = pDims.0 ?? sDims.0, let h = pDims.1 ?? sDims.1 {
            return MetadataRecommendation(
                field: "Dimensions",
                sourceValue: sDims.0 != nil ? "\(sDims.0!) × \(sDims.1!)" : nil,
                targetValue: pDims.0 != nil ? "\(pDims.0!) × \(pDims.1!)" : nil,
                recommendedValue: (w, h),
                reason: "Using the only available dimensions"
            )
        } else {
            return MetadataRecommendation(
                field: "Dimensions",
                sourceValue: nil,
                targetValue: nil,
                recommendedValue: nil,
                reason: "No dimension metadata available"
            )
        }
    }
    
    private func analyzeFileName(primary: ScannedFile, secondary: ScannedFile, group: DuplicateGroup) -> MetadataRecommendation {
        let pName = primary.fileName
        let sName = secondary.fileName
        
        // Check for meaningful names vs generic names
        let genericPatterns = ["IMG_", "DSC_", "DCIM", "image", "photo", ".tmp", "Copy"]
        
        let pIsGeneric = genericPatterns.contains { pName.contains($0) }
        let sIsGeneric = genericPatterns.contains { sName.contains($0) }
        
        var recommended = pName
        var reason = "Using primary file name"
        
        if !pIsGeneric && sIsGeneric {
            recommended = pName
            reason = "Primary file has more meaningful name"
        } else if pIsGeneric && !sIsGeneric {
            recommended = sName
            reason = "Secondary file has more meaningful name"
        } else if let date = primary.originalCreationDate ?? secondary.originalCreationDate {
            // Generate a meaningful name based on date and camera
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let dateStr = formatter.string(from: date)
            
            let camera = primary.cameraModel ?? secondary.cameraModel ?? "Photo"
            let cameraShort = camera.components(separatedBy: " ").first ?? "Photo"
            
            let ext = (pName as NSString).pathExtension
            recommended = "\(dateStr)_\(cameraShort).\(ext)"
            reason = "Generated meaningful name from metadata"
        }
        
        return MetadataRecommendation(
            field: "File Name",
            sourceValue: sName,
            targetValue: pName,
            recommendedValue: recommended,
            reason: reason
        )
    }
    
    func applyMergedMetadata(_ merged: MergedMetadata, to file: ScannedFile) {
        if let date = merged.originalCreationDate {
            file.originalCreationDate = date
        }
        if let camera = merged.cameraModel {
            file.cameraModel = camera
        }
        if let width = merged.width, let height = merged.height {
            file.width = width
            file.height = height
        }
        file.hasMetadata = merged.hasCompleteMetadata
    }
}