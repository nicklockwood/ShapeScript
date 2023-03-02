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
        case .union, .xor, .difference, .intersection, .stencil, .group,
             .camera, .light:
            return true
        case .cone, .cylinder, .sphere, .cube:
            return false
        case let .extrude(shapes, _),
             let .lathe(shapes, _),
             let .loft(shapes),
             let .fill(shapes):
            return shapes.isEmpty || shapes.allSatisfy { $0.points.count < 2 }
        case let .hull(points):
            return points.count < 2
        case let .path(path):
            return path.points.count < 2
        case let .mesh(mesh):
            return mesh.polygons.isEmpty
        }
    }

    /// Returns exact bounds, not including the effect of child shapes
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
                let pathBounds = path.bounds
                bounds.formUnion(pathBounds.translated(by: offset))
                bounds.formUnion(pathBounds.translated(by: -offset))
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
        case let .lathe(paths, segments):
            return .init(bounds: paths.map { path in
                let profileBounds = path.latheProfile.bounds
                let diameter = abs(profileBounds.min.x) * 2
                let bounds = Path.circle(segments: segments).bounds
                    .scaled(by: diameter)
                    .rotated(by: .roll(-.halfPi))
                    .rotated(by: .pitch(.halfPi))
                return bounds.translated(by: profileBounds.min.y * .unitY)
                    .union(bounds.translated(by: profileBounds.max.y * .unitY))
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

    /// Returns representative points needed to generate exact bounds
    var representativePoints: [Vector] {
        switch self {
        case .union, .xor, .difference, .intersection, .stencil,
             .group, .camera, .light:
            return []
        case .cube:
            return [
                Vector(-0.5, -0.5, -0.5),
                Vector(0.5, -0.5, -0.5),
                Vector(0.5, 0.5, -0.5),
                Vector(-0.5, 0.5, -0.5),
                Vector(-0.5, -0.5, 0.5),
                Vector(0.5, -0.5, 0.5),
                Vector(0.5, 0.5, 0.5),
                Vector(-0.5, 0.5, 0.5),
            ]
        case let .cone(segments):
            let points = Path.circle(segments: segments)
                .rotated(by: .roll(-.halfPi))
                .rotated(by: .pitch(.halfPi))
                .pointPositions
            return points.translated(by: Vector(0, -0.5, 0)) + [Vector(0, 0.5, 0)]
        case let .cylinder(segments):
            let points = Path.circle(segments: segments)
                .rotated(by: .roll(-.halfPi))
                .rotated(by: .pitch(.halfPi))
                .pointPositions
            return points.translated(by: Vector(0, -0.5, 0))
                + points.translated(by: Vector(0, 0.5, 0))
        case let .sphere(segments):
            let stacks = max(2, segments / 2)
            return GeometryType
                .lathe([.arc(segments: stacks)], segments: stacks)
                .representativePoints
        case let .extrude(paths, .default):
            return paths.reduce(into: []) { vertices, path in
                let offset = path.faceNormal / 2
                let points = path.pointPositions
                vertices += points.translated(by: offset) + points.translated(by: -offset)
            }
        case let .extrude(paths, options):
            return paths.flatMap { path in
                options.along.flatMap { along in
                    path.extrusionContours(
                        along: along,
                        twist: options.twist,
                        align: options.align
                    ).flatMap { $0.pointPositions }
                }
            }
        case let .lathe(paths, segments):
            return paths.flatMap { path -> [Vector] in
                let profile = path.latheProfile
                return profile.pointPositions.flatMap { point -> [Vector] in
                    let diameter = abs(point.x) * 2
                    let circle = Path.circle(segments: segments)
                        .scaled(by: diameter)
                        .rotated(by: .roll(-.halfPi))
                        .rotated(by: .pitch(.halfPi))
                    return circle
                        .translated(by: point.y * .unitY)
                        .pointPositions
                }
            }
        case let .loft(paths), let .fill(paths):
            return paths.flatMap { $0.pointPositions }
        case let .hull(vertices):
            // Note that this does not include child mesh vertices
            return vertices.map { $0.position }
        case let .path(path):
            return path.pointPositions
        case let .mesh(mesh):
            return mesh.vertexPositions
        }
    }
}

private extension Path {
    var pointPositions: [Vector] {
        points.map { $0.position }
    }
}

private extension Mesh {
    var vertexPositions: [Vector] {
        // TODO: find more efficient way to calculate this
        Array(Set(polygons.flatMap { $0.vertices.map { $0.position } }))
    }
}
