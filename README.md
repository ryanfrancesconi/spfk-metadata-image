# SPFKMetadataImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-metadata-image)](https://github.com/ryanfrancesconi/spfk-metadata-image/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)

XMP metadata reading and writing for image files, built entirely on Apple's [ImageIO](https://developer.apple.com/documentation/imageio) framework (`CGImageMetadata`/`CGImageDestination`) — no vendored SDK, no C++ bridging.

## Why this exists, not `spfk-metadata-xmp`

This workspace already has [`spfk-metadata-xmp`](https://github.com/ryanfrancesconi/spfk-metadata-xmp), a wrapper around Adobe's XMP Toolkit, built for ShadowTag's audio/video Dynamic Media metadata. It's the right tool for the formats its vendored SDK handles well (JPEG, TIFF-based RAW, MOV/WAV/AIFF). It is **not** the right tool for HEIC: verified directly against a real iPhone HEIC file with no pre-existing XMP — the Adobe SDK fails to write XMP into it at all ("Cannot put XMP into file"), and even XMP written into that same file by ImageIO can't be read back through the Adobe SDK's parser ("Failed to find an XMP chunk"). Since HEIC is the default capture format for iPhone photos, that's not a corner case.

ImageIO's own metadata APIs handle JPEG, HEIC, PNG, TIFF, and DNG uniformly through one code path.

## What it reads and writes

| Type | Description |
|------|-------------|
| **`ImageXMP`** | The entry points: read a whole `XMPMetadata` off a file, write one back, and the keyword shorthand both products use most |
| **`XMPMetadata`** | The field set — keywords, creators, title, description, copyright, city, state, country, sub-location, rating, label, label color, and the two accessibility fields |
| **`XMPField`** | One writable field, identified by its XMP path and namespace |

`XMPField` exists so a caller can say "empty this field" as distinct from "leave it alone", which
`XMPMetadata` alone cannot express — a `nil` or empty array there means "no new value". Its `path`
must stay the path the reader reads from: a clear targeting a different one looks exactly like the
clear silently not working. It carries both a prefixed path and a namespace URI, because ImageIO
addresses a property one way and the Adobe toolkit the other.

Writes replace the given fields wholesale rather than merging into them, while preserving everything
else already on the file — EXIF, other XMP — via `kCGImageDestinationMergeMetadata`. A test checks
that a pre-existing EXIF field survives a write unchanged. Writes go to a temporary file in the same
directory and then atomically replace the original, so a failure or crash mid-write cannot corrupt
it.

**Language-alternative fields are written through a dedicated path.** `dc:title`, `dc:description`,
`dc:rights` and the accessibility fields are alt-text properties, and writing one with a bare path
call crashed the process against a real, untouched iPhone HEIC while passing every time on synthetic
JPEG fixtures. That gap is why every field here is tested against real HEIC files, not just
synthetic ones.

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
