//
//  GeometryType.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 12/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

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
}

extension GeometryType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .group: return "group"
        case .cone: return "cone"
        case .cylinder: return "cylinder"
        case .sphere: return "sphere"
        case .cube: return "cube"
        case .extrude: return "extrusion"
        case .lathe: return "lathe"
        case .loft: return "loft"
        case .fill: return "fill"
        case .union: return "union"
        case .difference: return "difference"
        case .intersection: return "intersection"
        case .xor: return "xor"
        case .stencil: return "stencil"
        case .path: return "path"
        case .mesh: return "mesh"
        }
    }
}

public extension GeometryType {
    var isEmpty: Bool {
        switch self {
        case .group, .union, .xor, .difference, .intersection, .stencil:
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
        case .group, .union, .xor, .difference, .intersection, .stencil:
            return .empty
        case .cone, .cylinder, .sphere, .cube:
            return .init(min: .init(-0.5, -0.5, -0.5), max: .init(0.5, 0.5, 0.5))
        case let .extrude(paths, along: along):
            if along.isEmpty {
                var points = [Vector]()
                for path in paths {
                    let offset = path.faceNormal / 2
                    for p in path.points {
                        points.append(p.position + offset)
                        points.append(p.position - offset)
                    }
                }
                return .init(points: points)
            }
            var bounds = Bounds.empty
            for along in along {
                let alongBounds = along.bounds
                for path in paths {
                    let pathBounds = path.bounds
                    bounds = bounds.union(Bounds(
                        min: alongBounds.min + pathBounds.min,
                        max: alongBounds.max + pathBounds.max
                    ))
                }
            }
            return bounds
        case let .lathe(paths, _):
            var result = [Bounds]()
            for path in paths {
                var min = path.bounds.min, max = path.bounds.max
                min.x = Swift.min(Swift.min(Swift.min(min.x, -max.x), min.z), -max.z)
                max.x = -min.x
                min.z = min.x
                max.z = -min.x
                result.append(.init(min: min, max: max))
            }
            return .init(bounds: result)
        case let .loft(paths),
             let .fill(paths):
            return .init(bounds: Array(paths.map { $0.bounds }))
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
        case let .extrude(paths, along):
            return paths.count == 1 && along.count <= 1
        case let .lathe(paths, _), let .fill(paths):
            return paths.count == 1
        case .cone, .cylinder, .sphere, .cube, .loft, .path, .mesh, .group:
            return true
        case .union, .xor, .difference, .intersection, .stencil:
            return false
        }
    }
}
