//
//  GeometryType.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 12/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

public struct Camera: Hashable {
    public var hasPosition: Bool
    public var hasOrientation: Bool
    public var hasScale: Bool
    public var background: MaterialProperty?
    public var fov: Angle?
    public var width: Double?
    public var height: Double?
}

public struct Light: Hashable {
    public var hasPosition: Bool
    public var hasOrientation: Bool
    public var color: Color
    public var spread: Angle
    public var penumbra: Double
}

public enum GeometryType: Hashable {
    case group
    // primitives
    case cone(segments: Int)
    case cylinder(segments: Int)
    case sphere(segments: Int)
    case cube
    // builders
    case extrude([Path], along: [Path])
    case lathe([Path], segments: Int)
    case loft([Path])
    case fill([Path])
    // csg
    case union
    case difference
    case intersection
    case xor
    case stencil
    // shapes
    case path(Path)
    case mesh(Mesh)
    // special
    case camera(Camera)
    case light(Light)
}

public extension GeometryType {
    var isEmpty: Bool {
        switch self {
        case .union, .xor, .difference, .intersection, .stencil,
             .group, .camera, .light:
            return true
        case .cone, .cylinder, .sphere, .cube:
            return false
        case let .extrude(shapes, _),
             let .lathe(shapes, _),
             let .loft(shapes),
             let .fill(shapes):
            return shapes.isEmpty || shapes.allSatisfy { $0.points.count < 2 }
        case let .path(path):
            return path.points.count < 2
        case let .mesh(mesh):
            return mesh.polygons.isEmpty
        }
    }

    var bounds: Bounds {
        switch self {
        case .union, .xor, .difference, .intersection, .stencil,
             .group, .camera, .light:
            return .empty
        case .cone, .cylinder, .sphere, .cube:
            return .init(min: .init(-0.5, -0.5, -0.5), max: .init(0.5, 0.5, 0.5))
        case let .extrude(paths, along: along):
            if along.isEmpty {
                return paths.reduce(into: .empty) { bounds, path in
                    let offset = path.faceNormal / 2
                    bounds.formUnion(path.bounds.translated(by: offset))
                    bounds.formUnion(path.bounds.translated(by: -offset))
                }
            }
            return along.reduce(into: .empty) { bounds, along in
                let alongBounds = along.bounds
                bounds = paths.reduce(into: bounds) { bounds, path in
                    let pathBounds = path.bounds
                    let pathRadius = Swift.max(
                        pathBounds.min.length,
                        pathBounds.max.length
                    )
                    bounds.formUnion(Bounds(
                        min: alongBounds.min - Vector(size: pathRadius),
                        max: alongBounds.max + Vector(size: pathRadius)
                    ))
                }
            }
        case let .lathe(paths, _):
            return .init(bounds: paths.map {
                var min = $0.bounds.min, max = $0.bounds.max
                min.x = Swift.min(min.x, -max.x, min.z, -max.z)
                max.x = -min.x
                min.z = min.x
                max.z = -min.x
                return .init(min: min, max: max)
            })
        case let .loft(paths), let .fill(paths):
            return .init(bounds: paths.map { $0.bounds })
        case let .path(path):
            return path.bounds
        case let .mesh(mesh):
            return mesh.bounds
        }
    }
}

internal extension GeometryType {
    var isLeafGeometry: Bool {
        switch self {
        case let .extrude(paths, _), let .lathe(paths, _):
            return !paths.isEmpty
        case .cone, .cylinder, .sphere, .cube, .loft, .path, .mesh, .fill,
             .group, .camera, .light:
            return true
        case .union, .xor, .difference, .intersection, .stencil:
            return false
        }
    }
}
