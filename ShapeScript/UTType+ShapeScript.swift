//
//  UTType+ShapeScript.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 13/09/2026.
//

#if canImport(UniformTypeIdentifiers)

import UniformTypeIdentifiers

public extension UTType {
    /// The ShapeScript source document type, identified by the `.shape` filename extension.
    static let shape: Self = .init(
        exportedAs: "com.charcoaldesign.shapescript-source",
        conformingTo: .sourceCode
    )

    /// An evaluated OpenSCAD CSG document, identified by the `.csg` filename extension.
    static let csg: Self = .init(
        importedAs: "org.openscad.csg",
        conformingTo: .plainText
    )
}

#endif
