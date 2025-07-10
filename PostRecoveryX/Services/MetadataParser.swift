import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

actor MetadataParser {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    func parseMetadata(for file: ScannedFile) async throws {
        let url = URL(fileURLWithPath: file.path)
        
        guard let uti = UTType(filenameExtension: url.pathExtension) else {
            throw MetadataParserError.unsupportedFileType
        }
        
        if uti.conforms(to: .image) {
            try await parseImageMetadata(for: file, at: url)
        } else if uti.conforms(to: .movie) || uti.conforms(to: .video) {
            try await parseVideoMetadata(for: file, at: url)
        } else {
            throw MetadataParserError.unsupportedFileType
        }
    }
    
    private func parseImageMetadata(for file: ScannedFile, at url: URL) async throws {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MetadataParserError.cannotCreateImageSource
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw MetadataParserError.noMetadata
        }
        
        if let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int {
            file.width = pixelWidth
        }
        
        if let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int {
            file.height = pixelHeight
        }
        
        if let exifData = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateTimeOriginal = exifData[kCGImagePropertyExifDateTimeOriginal] as? String {
                file.originalCreationDate = dateFormatter.date(from: dateTimeOriginal)
                file.hasMetadata = true
            } else if let dateTimeDigitized = exifData[kCGImagePropertyExifDateTimeDigitized] as? String {
                file.originalCreationDate = dateFormatter.date(from: dateTimeDigitized)
                file.hasMetadata = true
            }
        }
        
        if let tiffData = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if file.originalCreationDate == nil,
               let dateTime = tiffData[kCGImagePropertyTIFFDateTime] as? String {
                file.originalCreationDate = dateFormatter.date(from: dateTime)
                file.hasMetadata = true
            }
            
            if let make = tiffData[kCGImagePropertyTIFFMake] as? String,
               let model = tiffData[kCGImagePropertyTIFFModel] as? String {
                file.cameraModel = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            }
        }
        
        if properties[kCGImagePropertyGPSDictionary] != nil {
            file.hasMetadata = true
        }
        
        if file.originalCreationDate == nil && file.creationDate != nil {
            file.originalCreationDate = file.creationDate
        }
    }
    
    private func parseVideoMetadata(for file: ScannedFile, at url: URL) async throws {
        let asset = AVAsset(url: url)
        
        do {
            let tracks = try await asset.load(.tracks)
            
            for track in tracks where track.mediaType == .video {
                let naturalSize = try await track.load(.naturalSize)
                file.width = Int(naturalSize.width)
                file.height = Int(naturalSize.height)
                break
            }
            
            let metadata = try await asset.load(.metadata)
            
            for item in metadata {
                if let key = item.key as? String {
                    switch key {
                    case "creationDate", "com.apple.quicktime.creationdate":
                        if let dateString = try await item.load(.stringValue),
                           let date = ISO8601DateFormatter().date(from: dateString) {
                            file.originalCreationDate = date
                            file.hasMetadata = true
                        }
                    case "make", "com.apple.quicktime.make":
                        if let make = try await item.load(.stringValue) {
                            file.cameraModel = make
                        }
                    case "model", "com.apple.quicktime.model":
                        if let model = try await item.load(.stringValue) {
                            if let existingMake = file.cameraModel {
                                file.cameraModel = "\(existingMake) \(model)"
                            } else {
                                file.cameraModel = model
                            }
                        }
                    default:
                        break
                    }
                }
            }
            
            if file.originalCreationDate == nil {
                let creationDate = try await asset.load(.creationDate)
                if let creationDateItem = creationDate {
                    let dateValue = try await creationDateItem.load(.dateValue)
                    if let date = dateValue {
                        file.originalCreationDate = date
                        file.hasMetadata = true
                    }
                }
            }
            
        } catch {
            throw MetadataParserError.videoMetadataError(error)
        }
    }
    
    func restoreFileDate(for file: ScannedFile) async throws {
        guard let originalDate = file.originalCreationDate,
              originalDate != file.creationDate else {
            return
        }
        
        let url = URL(fileURLWithPath: file.path)
        
        do {
            try FileManager.default.setAttributes(
                [.creationDate: originalDate, .modificationDate: originalDate],
                ofItemAtPath: url.path
            )
            
            file.creationDate = originalDate
            file.modificationDate = originalDate
        } catch {
            throw MetadataParserError.cannotSetFileDate(error)
        }
    }
}

enum MetadataParserError: LocalizedError {
    case unsupportedFileType
    case cannotCreateImageSource
    case noMetadata
    case videoMetadataError(Error)
    case cannotSetFileDate(Error)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type"
        case .cannotCreateImageSource:
            return "Cannot read image file"
        case .noMetadata:
            return "No metadata found"
        case .videoMetadataError(let error):
            return "Video metadata error: \(error.localizedDescription)"
        case .cannotSetFileDate(let error):
            return "Cannot set file date: \(error.localizedDescription)"
        }
    }
}