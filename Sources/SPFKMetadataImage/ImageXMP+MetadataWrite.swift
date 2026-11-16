// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKBase

extension ImageXMP {
    /// Two write mechanisms, chosen per field by ``XMPField``:
    /// - `.scalarProperty` goes through the `CGImageMetadataSetValueMatchingImageProperty` bridge,
    ///   for a field with a crosswalk.
    /// - `.namespacedTag` builds a tag under its namespace, at the shape `form` names.
    ///
    /// Two more start from the file's own metadata, so either one takes the clearing path:
    /// - `.structure` rebuilds a struct from its current children with each listed child set, or
    ///   removed where its value is `nil`, and drops the struct when none is left.
    /// - `.mirroredTag` sets or removes a second path, only where the file's metadata has it.
    enum MetadataWrite {
        case scalarProperty(dictionary: CFString, property: CFString, value: CFTypeRef)
        case namespacedTag(namespace: CFString, prefix: CFString, name: String, value: CFTypeRef, form: TagForm)
        case structure(namespace: CFString, prefix: CFString, name: String, children: [(name: String, value: String?)])
        case mirroredTag(namespace: CFString, prefix: CFString, name: String, value: CFString?)

        var startsFromFileMetadata: Bool {
            switch self {
            case .scalarProperty, .namespacedTag: false
            case .structure, .mirroredTag: true
            }
        }
    }

    enum TagForm {
        case scalar
        /// Set at the `[x-default]`-indexed path. A tag at the bare path of an `rdf:Alt` crashes.
        case alternateText
        case array(CGImageMetadataType)
    }

    static func write(_ field: XMPField, values: [String], url: URL) throws -> MetadataWrite {
        let value: CFTypeRef

        if field.shape == .integer {
            guard let number = Int(values[0]) else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
            }
            value = number as CFNumber
        } else if field.isArray {
            value = values as CFArray
        } else {
            value = values[0] as CFString
        }

        if let crosswalk = field.crosswalk {
            return .scalarProperty(dictionary: kCGImagePropertyIPTCDictionary, property: crosswalk, value: value)
        }

        let form: TagForm = switch field.shape {
        case .text, .integer, .bool, .struct: .scalar
        case .langAlt: .alternateText
        case .bag: .array(.arrayUnordered)
        case .seq: .array(.arrayOrdered)
        }

        return .namespacedTag(
            namespace: field.namespace as CFString, prefix: field.prefix as CFString,
            name: field.localName, value: value, form: form
        )
    }

    /// One `.structure` write per struct, carrying the children being set or removed.
    static func structureWrites(_ children: [(field: XMPField, value: String?)]) -> [MetadataWrite] {
        var names: [String] = []
        var byName: [String: [(field: XMPField, value: String?)]] = [:]

        for child in children {
            guard let name = child.field.structName else { continue }
            if byName[name] == nil { names.append(name) }
            byName[name, default: []].append(child)
        }

        return names.compactMap { name in
            guard let first = byName[name]?.first?.field else { return nil }

            return .structure(
                namespace: first.namespace as CFString, prefix: first.prefix as CFString, name: name,
                children: byName[name, default: []].map { ($0.field.localName, $0.value) }
            )
        }
    }

    /// Applies `writes` to `metadata`. `registeredPrefixes` are those already registered on it.
    static func apply(
        _ writes: [MetadataWrite],
        to metadata: CGMutableImageMetadata,
        registeredPrefixes: inout Set<String>,
        url: URL
    ) throws {
        func register(_ namespace: CFString, _ prefix: CFString) throws {
            // The bridge already knows the namespace of any classic property; a tag does not.
            guard !registeredPrefixes.contains(prefix as String) else { return }

            var registrationError: Unmanaged<CFError>?
            guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, &registrationError) else {
                throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
            }
            registeredPrefixes.insert(prefix as String)
        }

        func setTag(_ tag: CGImageMetadataTag?, at path: String) throws {
            guard let tag, CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag) else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
            }
        }

        for write in writes {
            switch write {
            case let .scalarProperty(dictionary, property, value):
                guard CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, property, value) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

            case let .namespacedTag(namespace, prefix, name, value, form):
                try register(namespace, prefix)

                let type: CGImageMetadataType = if case let .array(arrayType) = form { arrayType } else { .default }
                let path = if case .alternateText = form { "\(prefix):\(name)[x-default]" } else { "\(prefix):\(name)" }

                try setTag(CGImageMetadataTagCreate(namespace, prefix, name as CFString, type, value), at: path)

            case let .structure(namespace, prefix, name, children):
                try register(namespace, prefix)

                let path = "\(prefix):\(name)"
                let existing = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString)
                    .flatMap { CGImageMetadataTagCopyValue($0) } as? [String: CGImageMetadataTag]
                var fields = existing ?? [:]

                for (child, value) in children {
                    fields[child] = value.flatMap {
                        CGImageMetadataTagCreate(namespace, prefix, child as CFString, .default, $0 as CFString)
                    }
                }

                CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)

                if fields.isNotEmpty {
                    try setTag(CGImageMetadataTagCreate(namespace, prefix, name as CFString, .structure, fields as CFDictionary), at: path)
                }

            case let .mirroredTag(namespace, prefix, name, value):
                try register(namespace, prefix)

                let path = "\(prefix):\(name)"
                guard CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) != nil else { continue }

                if let value {
                    try setTag(CGImageMetadataTagCreate(namespace, prefix, name as CFString, .default, value), at: path)
                } else {
                    CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
                }
            }
        }
    }
}
