# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PostRecoveryX is a native macOS application for organizing images and removing duplicates after data recovery. Built with Swift and SwiftUI, it helps restore lost metadata and organize files into a Year/Month/TopFolder structure. The app is designed to handle large datasets (tested with 260,000+ files) from data recovery tools like PhotoRec and TestDisk.

## Core Architecture

### Actor-Based Concurrency Model
The application uses Swift actors for thread-safe concurrent operations:
- **DataActor**: Manages all SwiftData operations with batch processing for large datasets
- **FileScanner**: Discovers files with progress callbacks
- **DuplicateChecker**: SHA256 and perceptual hashing with caching
- **MetadataParser**: Extracts EXIF/video metadata
- **SceneDetector**: Groups similar photos (burst shots, sequences, events)
- **FolderOrganizer**: Manages file organization operations

### Performance Optimizations for Large Datasets
- Batch processing (1,000 files per batch for insertion, 5,000 for duplicate checking)
- Pagination in UI views (50 items per page)
- Lazy loading with SwiftUI's LazyVStack/LazyVGrid
- Background processing with Task.detached
- Performance monitoring with real-time metrics
- Dynamic configuration based on system capabilities

### Technology Stack
- **UI Framework**: SwiftUI with MVVM pattern
- **Data Persistence**: SwiftData with manual save control
- **Concurrency**: Swift actors and async/await
- **Testing**: Swift Testing framework (not XCTest)
- **Platform**: macOS 14.0+ (uses latest SwiftData features)
- **IDE**: Xcode 15.0+

## Development Commands

```bash
# Build the project (navigate to PostRecoveryX subdirectory first)
cd PostRecoveryX
xcodebuild -project PostRecoveryX.xcodeproj -scheme PostRecoveryX build

# Run tests (uses Swift Testing framework)
xcodebuild test -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -only-testing:PostRecoveryXTests

# Run a single test
xcodebuild test -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -only-testing:PostRecoveryXTests/PostRecoveryXTests/testName

# Build in quiet mode (recommended for large projects)
xcodebuild -project PostRecoveryX.xcodeproj -scheme PostRecoveryX build -quiet

# Quick build script (shows only errors/warnings)
./test_build_quick.sh

# Clean build folder
xcodebuild clean -project PostRecoveryX.xcodeproj -scheme PostRecoveryX

# Open built app
open /Users/nick/Library/Developer/Xcode/DerivedData/PostRecoveryX-*/Build/Products/Debug/PostRecoveryX.app

# Run automated test suite
./test_app.sh         # Standard test suite
./test_app.sh quick   # Quick test only
./test_app.sh full    # Full test suite including 100K files
./test_app.sh extreme # Extreme test with 1M files

# Generate test data
python3 test_postrecoveryx.py --quick           # 100 test files
python3 test_postrecoveryx.py                   # 1,000 test files
python3 test_postrecoveryx.py --massive 100000  # 100K test files
python3 test_postrecoveryx.py --cleanup         # Clean test data
```

## Key Implementation Details

### File Type Support
- **Images**: .jpg, .jpeg, .png, .heic, .heif, .tiff, .tif, .bmp, .gif, .webp, .svg, .ico, .icns
- **RAW Images**: .cr2, .cr3, .nef, .arw, .orf, .rw2, .dng, .raf, .srw, .crw, .raw
- **Videos**: .mp4, .mov, .avi, .mkv, .wmv, .flv, .webm, .m4v, .mpg, .mpeg, .3gp

### Essential Frameworks and APIs
```swift
import SwiftUI          // UI framework
import SwiftData        // Data persistence
import CryptoKit        // SHA256 hashing
import ImageIO          // Image metadata extraction
import AVFoundation     // Video metadata
import UniformTypeIdentifiers  // File type detection
import Vision           // For image analysis
import Charts          // Performance dashboard
```

### File Access and Permissions
The app is sandboxed with read-write file access (`com.apple.security.files.user-selected.read-write`). Features:
- NSOpenPanel for directory selection
- File operations use FileManager.default.trashItem() for safety
- Batch operations to handle large file counts efficiently

### SwiftData Models
- `ScannedFile`: Tracks file metadata, hashes, and duplicate status
- `DuplicateGroup`: Groups of identical or visually similar files
- `SimilarSceneGroup`: Groups of related photos (bursts, sequences, events)
- `ScanSession`: Tracks scanning progress and can be resumed
- `OrganizationTask`: Manages file organization operations
- `PerformanceData`: Stores performance metrics

### Concurrent Processing
Use Swift concurrency for performance:
```swift
// Example for parallel file processing
await withTaskGroup(of: FileInfo.self) { group in
    for path in filePaths {
        group.addTask { await processFile(at: path) }
    }
}
```

## Key Features and Implementation

### Duplicate Detection
- **Exact Matching**: SHA256 hash comparison
- **Visual Matching**: Enhanced perceptual hashing that detects rotated images
- **Rotation Detection**: Automatically identifies 90°, 180°, 270° rotations
- **Confidence Scoring**: Visual matches include confidence percentage

### Similar Scene Detection
Automatically groups photos by:
- **Burst Shots**: Photos taken within 2 seconds
- **Sequences**: Visually similar photos within 30 seconds
- **Events**: Photos from same folder within 1 hour

### Performance Features
- **Scan All File Types**: Discovers all files first, then filters by type
- **Resume Sessions**: Incomplete scans can be continued
- **Performance Dashboard**: Real-time monitoring of processing speed
- **Batch Operations**: Handles 260,000+ files efficiently

## Testing Approach

The project uses Swift Testing framework (not XCTest). Tests are in `PostRecoveryXTests/PostRecoveryXTests.swift`.

### Test Pattern
```swift
import Testing
import SwiftData
import Foundation
import AppKit  // Required for NSImage/NSColor
@testable import PostRecoveryX

struct TestName {
    @Test func testFunction() async throws {
        // For tests needing SwiftData context:
        let (container, context, dataActor) = try await MainActor.run {
            try PostRecoveryXTests.createTestContainer()
        }
        // Test implementation
    }
}
```

### Test Infrastructure
- **Automated Testing**: `test_app.sh` runs performance tests with real data
- **Test Data Generator**: `test_postrecoveryx.py` creates realistic test scenarios
- **Performance Monitoring**: Tracks CPU/memory usage during tests
- **Scalability Testing**: Supports testing with up to 1M files

## UI Components and Navigation

### Main Tabs
1. **Scan**: File discovery and processing initiation
2. **Duplicates**: Paginated view with 50 items per page (OptimizedDuplicateManagementView)
3. **Similar Scenes**: Groups burst shots, sequences, and events
4. **Thumbnails**: Bulk management of small/thumbnail images
5. **Organize**: File organization into Year/Month structure
6. **History**: Previous scan sessions

### Key UI Patterns
- **Pagination**: Large datasets use fetchLimit/fetchOffset
- **Lazy Loading**: LazyVStack/LazyVGrid for memory efficiency
- **Progress Tracking**: Multi-phase progress with time estimates
- **Session Recovery**: Prompts to continue incomplete scans

## Error Handling and Edge Cases

```swift
// DataActor handles SwiftData operations with proper error propagation
// FileScanner handles missing permissions gracefully
// DuplicateChecker caches results to avoid re-processing
// MetadataParser falls back to file system dates if EXIF missing
```

## Important Implementation Notes

1. **Project Structure**: Main code is in PostRecoveryX/PostRecoveryX/ subdirectory
2. **Database Migration**: App automatically handles SwiftData schema changes
3. **Testing**: Tests have been updated to use Swift Testing framework. Remove .bak files from PostRecoveryXTests/ before running
4. **Performance**: Tested with 260,000+ files - uses batching and pagination
5. **Concurrency**: All heavy operations use actors for thread safety
6. **Data Transfer**: Uses Sendable structs (FileInfo, DuplicateGroupInfo) for cross-actor communication
7. **Memory Management**: SwiftData models stay within DataActor boundary to prevent concurrency issues