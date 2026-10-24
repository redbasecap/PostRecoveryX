# PostRecoveryX

A native macOS app (Swift + SwiftUI + SwiftData) for cleaning up after a
data recovery with tools like PhotoRec or TestDisk, which leave you with
hundreds of thousands of files without their original names or folders.

- Scans recovered folders and finds exact duplicates (SHA-256) and
  visually similar images (perceptual hashing).
- Reads EXIF and video metadata to recover capture dates.
- Groups similar photos (bursts, sequences, events).
- Organizes files into `Year/Month` folders.
- Built for large sets (tested with 260,000+ files): batched processing,
  paginated views, background work.

## Requirements

- macOS 14 or later
- Xcode 15 or later

## Build and run

```bash
git clone https://github.com/redbasecap/PostRecoveryX.git
cd PostRecoveryX
open PostRecoveryX.xcodeproj   # then press Run in Xcode
```

Or from the command line:

```bash
xcodebuild -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/PostRecoveryX.app
```

If you do not have a signing team set up, add `CODE_SIGNING_ALLOWED=NO` to the
`xcodebuild` command, or pick your own team under Signing & Capabilities.
