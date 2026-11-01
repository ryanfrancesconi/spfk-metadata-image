# SPFKMetadataImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-metadata-image)](https://github.com/ryanfrancesconi/spfk-metadata-image/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)

XMP for image files, read and written through Apple's ImageIO rather than a vendored toolkit. It is
the shared field set for descriptive image metadata (keywords, creators, title, description,
copyright, location, rating, label and the accessibility text), used by the products directly and by
[spfk-metadata-xmp](https://github.com/ryanfrancesconi/spfk-metadata-xmp)'s `VideoXMP`, so an image
and a video support the same fields.

It exists beside spfk-metadata-xmp because the Adobe toolkit cannot write XMP into a HEIC, the
default iPhone capture format, nor read back what ImageIO wrote there. ImageIO handles JPEG, HEIC,
PNG and TIFF through one path. It cannot write DNG; DNG writes go through spfk-metadata-xmp.

A write replaces the given fields and keeps everything else on the file, EXIF and other XMP
included, and replaces the original atomically.

## Clearing a field

`XMPField` is how a caller says "empty this field" as distinct from "leave it alone", which a `nil`
in `XMPMetadata` cannot express. A field's path must be the path the reader reads from, or a clear
looks exactly like a clear that silently did nothing.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
