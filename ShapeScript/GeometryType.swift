//
//  GeometryType.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 12/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

public struct Camera: Hashable {
    public var position: Vector?
    public var orientation: Rotation?
    public var scale: Vector?
    public var background: MaterialProperty?
    public var fov: Angle?
    public var width: Double?
    public var height: Double?
}

public extension Camera {
    var hasPosition: Bool { position != nil }

    var hasOrientation: Bool { orientation != nil }

    var hasScale: Bool { scale != nil }
}

public struct Light: Hashable {
    public var position: Vector?
    public var orientation: Rotation?
    public var color: Color
    public var spread: Angle
    public var penumbra: Double
}

public extension Light {
    var hasPosition: Bool { position != nil }

    var hasOrientation: Bool { orientation != nil }
}

public struct ExtrudeOptions: Hashable {
    public var along: [Path]
    public var twist: Angle
    public var align: Path.Alignment

    public static let `default`: Self = .init()

    init(along: [Path] = [], twist: Angle? = nil, align: Path.Alignment? = nil) {
        self.along = along
        self.twist = twist ?? .zero
        self.align = (along.isEmpty ? nil : align) ?? .default
    }
}

public enum GeometryType: Hashable {
    case group
    // primitives
    case cone(segments: Int)
    case cylinder(segments: Int)
    case sphere(segments: Int)
    case cube
    // builders
    case extrude([Path], ExtrudeOptions)
    case lathe([Path], segments: Int)
    case loft([Path])
    case fill([Path])
    case hull([Vertex])
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
             .group, .hull, .camera, .light:
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
        case .cube:
            return .init(min: .init(-0.5, -0.5, -0.5), max: .init(0.5, 0.5, 0.5))
        case let .cone(segments), let .cylinder(segments), let .sphere(segments):
            let bounds = Path.circle(segments: segments).bounds
                .rotated(by: .roll(-.halfPi))
            return Bounds(
                min: .init(bounds.min.x, -0.5, bounds.min.y),
                max: .init(bounds.max.x, 0.5, bounds.max.y)
            )
        case let .extrude(paths, .default):
            return paths.reduce(into: .empty) { bounds, path in
                let offset = path.faceNormal / 2
                bounds.formUnion(path.bounds.translated(by: offset))
                bounds.formUnion(path.bounds.translated(by: -offset))
            }
        case let .extrude(paths, options):
            return paths.flatMap { path in
                options.along.flatMap { along in
                    path.extrusionContours(
                        along: along,
                        twist: options.twist,
                        align: options.align
                    )
                }
            }.bounds
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
        case let .hull(vertices):
            return .init(points: vertices.map { $0.position })
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
        case .hull, .union, .xor, .difference, .intersection, .stencil:
            return false
        }
    }
}
