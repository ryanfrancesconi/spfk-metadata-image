# SPFKMetadataImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-metadata-image)](https://github.com/ryanfrancesconi/spfk-metadata-image/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-metadata-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-metadata-image)

Reads and writes XMP in image files through ImageIO. It covers keywords, creators, title,
description, copyright, location, rating, label and accessibility text. A write replaces the given
fields, keeps all other metadata in the file, and replaces the file atomically.

## Features

- Read and write any format ImageIO can write, including HEIC
- `XMPField` clears a field, which a `nil` in `XMPMetadata` cannot express
- DNG is not writable through ImageIO; use
  [spfk-metadata-xmp](https://github.com/ryanfrancesconi/spfk-metadata-xmp) for it

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
