//
//  SVGImport.swift
//  ShapeScript
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

extension SVGDocument {
    func geometry(
        options: SVGImportOptions,
        material: Material = .default,
        fileURL: URL? = nil,
        isCancelled: @escaping CancellationHandler,
        warn: @escaping (String, Int) -> Void
    ) throws -> Geometry {
        let material = options.csg ? .default : material
        var options = options
        options.paintOverride = material.albedo.map { _ in material.color ?? .white }
        let root = try shapes(options: options, isCancelled: isCancelled, warn: warn)
        func geometry(_ shape: SVGGeometry) throws -> Geometry {
            if isCancelled() { throw CancellationError() }
            let location = shape.line.map { SourceLocation(at: $0, in: fileURL) }
            return try Geometry(
                type: shape.path.map(GeometryType.path) ?? .group, name: shape.id, transform: .identity,
                material: material, smoothing: .zero, children: shape.children.map(geometry),
                sourceLocation: location.map { location in { @Sendable in location } }
            )
        }
        return try geometry(root)
    }
}
