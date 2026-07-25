# SPFKMetadataImage

[![CI](https://img.shields.io/github/actions/workflow/status/ryanfrancesconi/spfk-metadata-image/ci.yml?branch=development)](https://github.com/ryanfrancesconi/spfk-metadata-image/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-metadata-image)](https://github.com/ryanfrancesconi/spfk-metadata-image/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)

XMP metadata reading and writing for image files, built entirely on Apple's [ImageIO](https://developer.apple.com/documentation/imageio) framework (`CGImageMetadata`/`CGImageDestination`) — no vendored SDK, no C++ bridging.

## Why this exists, not `spfk-metadata-xmp`

This workspace already has [`spfk-metadata-xmp`](https://github.com/ryanfrancesconi/spfk-metadata-xmp), a wrapper around Adobe's XMP Toolkit, built for ShadowTag's audio/video Dynamic Media metadata. It's the right tool for the formats its vendored SDK handles well (JPEG, TIFF-based RAW, MOV/WAV/AIFF). It is **not** the right tool for HEIC: verified directly against a real iPhone HEIC file with no pre-existing XMP — the Adobe SDK fails to write XMP into it at all ("Cannot put XMP into file"), and even XMP written into that same file by ImageIO can't be read back through the Adobe SDK's parser ("Failed to find an XMP chunk"). Since HEIC is the default capture format for iPhone photos, that's not a corner case.

ImageIO's own metadata APIs handle JPEG, HEIC, PNG, TIFF, and DNG uniformly through one code path, with no format-specific gaps found so far.

## Usage

```swift
import SPFKMetadataImage

let keywords = try ImageXMP.keywords(from: imageURL)  // [String], [] if none

try ImageXMP.setKeywords(["mountains", "california", "sunset"], url: imageURL)
```

`setKeywords` replaces the whole keyword set (`dc:subject`, an `rdf:Bag`) — it's not additive. All other existing metadata (EXIF, other XMP fields) is preserved via `kCGImageDestinationMergeMetadata`, verified by a test that checks a pre-existing EXIF field survives a keyword write unchanged. Writes go to a temporary file in the same directory, then atomically replace the original via `FileManager.replaceItemAt` — a failure or crash mid-write can't corrupt the original file.

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Core utilities and extensions |
| [spfk-testing](https://github.com/ryanfrancesconi/spfk-testing) | Test infrastructure (test target only) |

## Requirements

- **Platforms:** macOS 13+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
