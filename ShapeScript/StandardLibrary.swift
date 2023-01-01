//
//  StandardLibrary.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 18/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(SVGPath)
import SVGPath
#endif

/// Standard library symbols. Useful for syntax highlighting
public let stdlibSymbols: Set<String> = {
    var keys = Set<String>()
    for (key, symbol) in Symbols.all {
        keys.insert(key)
        switch symbol {
        case let .block(type, _):
            keys.formUnion(type.options.keys)
        case .function, .property, .constant, .option, .placeholder:
            break
        }
    }
    return keys
}()

extension Dictionary where Key == String, Value == Symbol {
    static func + (lhs: Symbols, rhs: Symbols) -> Symbols {
        lhs.merging(rhs) { $1 }
    }

    static let transform: Symbols = [
        "position": .property(.vector, { parameter, context in
            context.transform.offset = parameter.vectorValue
        }, { context in
            .vector(context.transform.offset)
        }),
        "orientation": .property(.rotation, { parameter, context in
            context.transform.rotation = parameter.rotationValue
        }, { context in
            .rotation(context.transform.rotation)
        }),
        "size": .property(.size, { parameter, context in
            context.transform.scale = parameter.vectorValue
        }, { context in
            .size(context.transform.scale)
        }),
    ]

    static let childTransform: Symbols = [
        "translate": .command(.vector) { parameter, context in
            let vector = parameter.vectorValue
            context.childTransform.translate(by: vector)
        },
        "rotate": .command(.rotation) { parameter, context in
            let rotation = parameter.rotationValue
            context.childTransform.rotate(by: rotation)
        },
        "scale": .command(.size) { parameter, context in
            let scale = parameter.vectorValue
            context.childTransform.scale(by: scale)
        },
    ]

    static let colors: Symbols = [
        "white": .constant(.color(.white)),
        "black": .constant(.color(.black)),
        "gray": .constant(.color(.gray)),
        "grey": .constant(.color(.gray)),
        "red": .constant(.color(.red)),
        "green": .constant(.color(.green)),
        "blue": .constant(.color(.blue)),
        "yellow": .constant(.color(.yellow)),
        "cyan": .constant(.color(.cyan)),
        "magenta": .constant(.color(.magenta)),
        "orange": .constant(.color(.orange)),
    ]

    static let color: Symbols = colors + [
        "color": .property(.color, { parameter, context in
            context.material.albedo = parameter.colorOrTextureValue
        }, { context in
            .color(context.material.color ?? .white)
        }),
    ]

    static let material: Symbols = color + [
        "opacity": .property(.numberOrTexture, { parameter, context in
            switch parameter {
            case let .number(opacity):
                let opacity = opacity * context.opacity
                context.material.opacity = .color(.init(opacity, opacity))
            case let .texture(texture):
                guard let texture = texture else { fallthrough }
                let opacity = texture.intensity * context.opacity
                context.material.opacity = .texture(texture.withIntensity(opacity))
            default:
                let opacity = context.opacity
                context.material.opacity = .color(.init(opacity, opacity))
            }
        }, { context in
            switch context.material.opacity ?? .color(.white) {
            case let .color(color):
                return .number(color.a / context.opacity)
            case let .texture(texture):
                // Since user cannot specify texture opacity, this should always be 1
                let opacity = texture.intensity / context.opacity
                return .texture(texture.withIntensity(opacity))
            }
        }),
        "texture": .property(.texture, { parameter, context in
            context.material.albedo = parameter.colorOrTextureValue
        }, { context in
            .texture(context.material.texture)
        }),
        "normals": .property(.texture, { parameter, context in
            context.material.normals = parameter.value as? Texture
        }, { context in
            .texture(context.material.normals)
        }),
        "metallicity": .property(.numberOrTexture, { parameter, context in
            context.material.metallicity = parameter.numberOrTextureValue
        }, { context in
            .numberOrTexture(context.material.metallicity ?? .color(.black))
        }),
        "roughness": .property(.numberOrTexture, { parameter, context in
            context.material.roughness = parameter.numberOrTextureValue
        }, { context in
            .numberOrTexture(context.material.roughness ?? .color(.black))
        }),
        "glow": .property(.colorOrTexture, { parameter, context in
            context.material.glow = parameter.colorOrTextureValue
        }, { context in
            .colorOrTexture(context.material.glow ?? .color(.black))
        }),
        "material": .property(.material, { parameter, context in
            context.material = parameter.value as? Material ?? .default
        }, { context in
            .material(context.material)
        }),
    ]

    static let polygons: Symbols = [
        "polygon": .block(.init(.polygon, [:], .point, .list(.polygon))) { context in
            let path = Path(context.children.compactMap {
                $0.value as? PathPoint
            }).transformed(by: context.transform)
            let polygons = path.closed().facePolygons(material: context.material)
            return .tuple(polygons.map { .polygon($0) })
        },
    ]

    static let meshes: Symbols = [
        // primitives
        "cone": .block(.shape) { context in
            .mesh(Geometry(type: .cone(segments: context.detail), in: context))
        },
        "cylinder": .block(.shape) { context in
            .mesh(Geometry(type: .cylinder(segments: context.detail), in: context))
        },
        "sphere": .block(.shape) { context in
            .mesh(Geometry(type: .sphere(segments: context.detail), in: context))
        },
        "cube": .block(.shape) { context in
            .mesh(Geometry(type: .cube, in: context))
        },
        // container
        "group": .block(.group) { context in
            .mesh(Geometry(type: .group, in: context))
        },
        // builders
        "extrude": .block(.init(.builder, [
            "along": .list(.path),
            "twist": .halfturns,
            "axisAligned": .boolean,
        ], .path, .list(.mesh))) { context in
            let twist = context.value(for: "twist")?.angleValue ?? .zero
            let align: Path.Alignment = context.value(for: "axisAligned").map {
                $0.boolValue ? .axis : .tangent
            } ?? .default
            if let along = context.value(for: "along")?.tupleValue as? [Path] {
                // shapes follow a common path
                // TODO: modify this to reuse meshes where possible
                return .mesh(Geometry(type: .extrude(context.paths, .init(
                    along: along.map {
                        $0.withDetail(context.detail, twist: twist)
                    },
                    twist: twist,
                    align: align
                )), in: context))
            }
            if twist == .zero {
                // Fast path - can reuse meshes (good for text)
                // TODO: modify to return separate meshes rather than union
                return .mesh(Geometry(
                    type: .extrude(context.paths, .default),
                    in: context
                ))
            }
            // Slow path, each calculated separately, no reuse
            // TODO: modify this to reuse meshes where possible
            return .tuple(context.paths.map {
                let vector = $0.faceNormal / 2
                let along = Path.line(-vector, vector)
                    .withDetail(context.detail, twist: twist)
                return .mesh(Geometry(type: .extrude([$0], .init(
                    along: [along],
                    twist: twist,
                    align: align
                )), in: context))
            })
        },
        "lathe": .block(.builder) { context in
            .mesh(Geometry(
                type: .lathe(context.paths, segments: context.detail),
                in: context
            ))
        },
        "loft": .block(.builder) { context in
            .mesh(Geometry(type: .loft(context.paths), in: context))
        },
        "fill": .block(.builder) { context in
            .mesh(Geometry(type: .fill(context.paths), in: context))
        },
        "hull": .block(.init(.hull, [:], .union([.point, .path, .mesh]), .mesh)) { context in
            let vertices = try context.children.flatMap { child -> [Vertex] in
                switch child {
                case let .point(point):
                    return [Vertex(point)]
                case let .path(path):
                    return path.subpaths.flatMap { $0.edgeVertices }
                case let .mesh(geometry):
                    if let path = geometry.path {
                        return path.subpaths.flatMap { $0.edgeVertices }
                    }
                    return [] // handled at mesh generation time
                default:
                    throw RuntimeErrorType.assertionFailure(
                        "Unexpected child of type \(child.type) in hull"
                    )
                }
            }
            return .mesh(Geometry(type: .hull(vertices), in: context))
        },
        // mesh
        "mesh": .block(.init(.mesh, [:], .polygon, .mesh)) { context in
            let polygons = context.children.compactMap { $0.value as? Polygon }
            return .mesh(Geometry(type: .mesh(Mesh(polygons)), in: context))
        },
        // csg
        "union": .block(.group) { context in
            .mesh(Geometry(type: .union, in: context))
        },
        "difference": .block(.group) { context in
            .mesh(Geometry(type: .difference, in: context))
        },
        "intersection": .block(.group) { context in
            .mesh(Geometry(type: .intersection, in: context))
        },
        "xor": .block(.group) { context in
            .mesh(Geometry(type: .xor, in: context))
        },
        "stencil": .block(.group) { context in
            .mesh(Geometry(type: .stencil, in: context))
        },
        // lights
        "light": .block(.init(.node, [
            "position": .vector,
            "orientation": .rotation,
            "color": .color,
            "spread": .halfturns,
            "penumbra": .number,
            "shadow": .number,
        ], .void, .mesh)) { context in
            let position = context.value(for: "position")?.value as? Vector
            position.map { context.transform.offset = $0 }
            let orientation = context.value(for: "orientation")?.value as? Rotation
            orientation.map { context.transform.rotation = $0 }
            return .mesh(Geometry(
                type: .light(Light(
                    position: position,
                    orientation: orientation,
                    color: context.value(for: "color")?.colorValue ?? .white,
                    spread: context.value(for: "spread")?.angleValue ?? (.pi / 4),
                    penumbra: context.value(for: "penumbra")?.doubleValue ?? 1,
                    shadowOpacity: context.value(for: "shadow")?.doubleValue ?? 0
                )),
                in: context
            ))
        },
        // debug
        "debug": .block(.group) { context in
            for case let .mesh(geometry) in context.children {
                geometry.debug = true
            }
            if context.children.count == 1,
               case let .mesh(child) = context.children[0]
            {
                return .mesh(child)
            }
            return .mesh(Geometry(type: .group, in: context))
        },
    ]

    static let paths: Symbols = [
        "path": .block(.path) { context in
            var subpaths = [Path]()
            var points = [PathPoint]()
            func endPath() {
                if !points.isEmpty {
                    subpaths.append(.curve(points, detail: context.detail / 4))
                }
                points.removeAll()
            }
            for child in context.children {
                switch child {
                case let .point(point):
                    points.append(point)
                case let .path(path):
                    endPath()
                    subpaths.append(path)
                case .tuple:
                    // Special case due to tuple type returning element type
                    throw RuntimeErrorType.assertionFailure(
                        "Unexpected child of type tuple in path"
                    )
                default:
                    throw RuntimeErrorType.assertionFailure(
                        "Unexpected child of type \(child.errorDescription) in path"
                    )
                }
            }
            endPath()
            if subpaths.count != 1 {
                subpaths = [Path(subpaths: subpaths)]
            }
            return .path(subpaths[0].transformed(by: context.transform))
        },
        "arc": .block(.init(.polygon, [
            "angle": .halfturns,
        ], .void, .list(.point))) { context in
            let angle = context.value(for: "angle")?.angleValue ?? .pi
            let span = Swift.max(0, Swift.min(1, abs(angle.radians) / (2 * .pi)))
            var segments = Int(ceil(span * Double(context.detail)))
            switch span {
            case 0 ..< 0.5:
                segments = Swift.max(1, segments)
            case 0.5 ..< 1:
                segments = Swift.max(2, segments)
            default:
                segments = Swift.max(3, segments)
            }
            return .path(Path.arc(
                angle: angle,
                segments: segments,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "circle": .block(.pathShape) { context in
            .path(Path.circle(
                segments: context.detail,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "square": .block(.pathShape) { context in
            .path(Path.square(
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "polygon": .block(.init(.polygon, [
            "sides": .number,
        ], .optional(.point), .union([.path, .list(.polygon)]))) { context in
            let sides = context.value(for: "sides")?.intValue
            let points = context.children.compactMap { $0.value as? PathPoint }
            if !points.isEmpty {
                if sides != nil {
                    throw RuntimeErrorType.assertionFailure("Polygon cannot have both sides and points")
                }
                let path = Path(points).transformed(by: context.transform)
                let polygons = path.closed().facePolygons(material: context.material)
                return .tuple(polygons.map { .polygon($0) })
            }
            return .path(Path.polygon(
                sides: sides ?? 5,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "roundrect": .block(.init(.pathShape, [
            "radius": .number,
            "size": .size,
        ], .void, .path)) { context in
            let size = context.value(for: "size")?.value as? Vector ?? .one
            let scale = Swift.min(size.x, size.y)
            let radius = (context.value(for: "radius")?.doubleValue ?? 0.25) * scale
            return .path(Path.roundedRectangle(
                width: size.x,
                height: size.y,
                radius: radius,
                detail: context.detail / 4,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "text": .block(.init(.pathShape, [
            "font": .font,
            "wrapwidth": .number,
            "linespacing": .number,
        ], .text, .list(.path))) { context in
            let width = context.value(for: "wrapwidth")?.doubleValue
            let text = context.children.compactMap { $0.value as? TextValue }
            let paths = Path.text(text, width: width, detail: context.detail / 8)
            return .tuple(paths.map { .path($0.transformed(by: context.transform)) })
        },
        "svgpath": .block(.init(.pathShape, [:], .string, .path)) { context in
            let text = context.children.map { $0.stringValue }.joined(separator: "\n")
            let svgPath: SVGPath
            do {
                svgPath = try SVGPath(string: text)
            } catch let error as SVGError {
                throw RuntimeErrorType.assertionFailure(error.message)
            }
            return .path(Path(
                svgPath,
                detail: context.detail / 4,
                color: context.material.color
            ).transformed(by: context.transform))
        },
    ]

    static let points: Symbols = [
        "point": .command(.vector) { parameter, context in
            try context.addValue(.point(.point(
                parameter.vectorValue,
                color: context.material.color
            )))
        },
    ]

    static let pathPoints: Symbols = _merge(points, [
        "curve": .command(.vector) { parameter, context in
            try context.addValue(.point(.curve(
                parameter.vectorValue,
                color: context.material.color
            )))
        },
    ])

    static let functions: Symbols = [
        // Debug
        "print": .command(.list(.any)) { value, context in
            context.debugLog(value.tupleValue)
        },
        "assert": .command(.boolean) { value, _ in
            if !value.boolValue {
                throw RuntimeErrorType.assertionFailure("")
            }
        },
        // Logic
        "true": .constant(.boolean(true)),
        "false": .constant(.boolean(false)),
        "not": .function(.boolean, .boolean) { value, _ in
            .boolean(!value.boolValue)
        },
        // Randomness
        "rnd": .function(.void, .number) { _, context in
            .number(context.random.next())
        },
        "seed": .property(.number, { value, context in
            context.random = RandomSequence(seed: value.doubleValue)
        }, { context in
            .number(Double(context.random.seed))
        }),
        // Math
        "abs": .function(.number, .number) { value, _ in
            .number(value.doubleValue.magnitude)
        },
        "sign": .function(.number, .number) { value, _ in
            switch value.doubleValue {
            case 0: return .number(0)
            case ..<0: return .number(-1)
            default: return .number(1)
            }
        },
        "ceil": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded(.up))
        },
        "floor": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded(.down))
        },
        "round": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded())
        },
        "max": .function(.list(.number), .number) { value, _ in
            .number(value.doublesValue.max() ?? 0)
        },
        "min": .function(.list(.number), .number) { value, _ in
            .number(value.doublesValue.min() ?? 0)
        },
        "sqrt": .function(.number, .number) { value, _ in
            .number(sqrt(value.doubleValue))
        },
        "pow": .function(.numberPair, .number) { value, _ in
            let values = value.doublesValue
            return .number(pow(values[0], values[1]))
        },
        // Trigonometry
        "cos": .function(.radians, .number) { value, _ in
            .number(cos(value.doubleValue))
        },
        "acos": .function(.number, .radians) { value, _ in
            .radians(acos(value.doubleValue))
        },
        "sin": .function(.radians, .number) { value, _ in
            .number(sin(value.doubleValue))
        },
        "asin": .function(.number, .radians) { value, _ in
            .radians(asin(value.doubleValue))
        },
        "tan": .function(.radians, .number) { value, _ in
            .number(tan(value.doubleValue))
        },
        "atan": .function(.number, .radians) { value, _ in
            .radians(atan(value.doubleValue))
        },
        "atan2": .function(.numberPair, .radians) { value, _ in
            let values = value.doublesValue
            return .radians(atan2(values[0], values[1]))
        },
        "pi": .constant(.number(.pi)),
        // Linear algebra
        "dot": .function(.tuple([.list(.number), .list(.number)]), .number) { value, _ in
            let values = value.tupleValue as! [[Double]]
            return .number(zip(values[0], values[1]).map { $0 * $1 }.reduce(0, +))
        },
        "cross": .function(.tuple([.vector, .vector]), .list(.number)) { value, _ in
            let values = value.tupleValue as! [Vector]
            return .tuple(values[0].cross(values[1]).components.map { .number($0) })
        },
        "length": .function(.list(.number), .number) { value, _ in
            let values = value.tupleValue as! [Double]
            return .number(sqrt(values.map { $0 * $0 }.reduce(0, +)))
        },
        "normalize": .function(.list(.number), .list(.number)) { value, _ in
            let values = value.tupleValue as! [Double]
            let length = sqrt(values.map { $0 * $0 }.reduce(0, +))
            return .tuple(values.map { .number(length > 0 ? $0 / length : 0) })
        },
        // Strings
        "split": .function(.tuple([.string, .string]), .list(.string)) { value, _ in
            let string = value.tupleValue[0] as! String
            let separator = value.tupleValue[1] as! String
            return .tuple(string
                .components(separatedBy: separator)
                .map { .string($0) })
        },
        "join": .function(.tuple([.list(.any), .string]), .string) { value, _ in
            guard case let .tuple(args) = value, args.count == 2,
                  case let .tuple(stringValues) = args[0],
                  case let .string(separator) = args[1]
            else {
                throw RuntimeErrorType.assertionFailure(
                    "Invalid arguments to join function"
                )
            }
            let strings = stringValues.map { $0.stringValue }
            return .string(strings.joined(separator: separator))
        },
        "trim": .function(.string, .string) { value, _ in
            .string(value.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ))
        },
        // Object
        "object": .block(.init([:], ["*": .any], .void, .any)) { context in
            var result = [String: ShapeScript.Value]()
            for name in context.options.keys {
                result[name] = context.value(for: name)
            }
            return .object(result)
        },
    ]

    static let name: Symbols = [
        "name": .property(.string, { parameter, context in
            context.name = parameter.stringValue
        }, { context in
            .string(context.name)
        }),
    ]

    static let background: Symbols = [
        "background": .getter(.colorOrTexture) { context in
            .colorOrTexture(context.background ?? .color(.clear))
        },
    ]

    static let font: Symbols = [
        "font": .property(.font, { parameter, context in
            context.font = parameter.stringValue
        }, { context in
            .string(context.font)
        }),
    ]

    static let detail: Symbols = [
        "detail": .property(.number, { parameter, context in
            // TODO: throw error if min/max detail level exceeded
            context.detail = Swift.max(0, parameter.intValue)
        }, { context in
            .number(Double(context.detail))
        }),
    ]

    static let smoothing: Symbols = [
        "smoothing": .property(.halfturns, { parameter, context in
            // TODO: find a better way to represent null/auto
            let angle = Swift.min(.pi, parameter.angleValue ?? .zero)
            context.smoothing = angle < .zero ? nil : angle
        }, { context in
            .halfturns(context.smoothing.map { $0.halfturns } ?? -1)
        }),
    ]

    static let root: Symbols = _merge(global, font, detail, smoothing, material, childTransform, [
        "camera": .block(.init(.node, [
            "position": .vector,
            "orientation": .rotation,
            "size": .size,
            "background": .colorOrTexture,
            "antialiased": .boolean,
            "fov": .halfturns,
            "width": .number,
            "height": .number,
        ], .void, .mesh)) { context in
            let position = context.value(for: "position")?.value as? Vector
            position.map { context.transform.offset = $0 }
            let orientation = context.value(for: "orientation")?.value as? Rotation
            orientation.map { context.transform.rotation = $0 }
            let scale = context.value(for: "size")?.value as? Vector
            scale.map { context.transform.scale = $0 }
            return .mesh(Geometry(
                type: .camera(Camera(
                    position: position,
                    orientation: orientation,
                    scale: scale,
                    background: context.value(for: "background")?.colorOrTextureValue,
                    antialiased: context.value(for: "antialiased")?.boolValue ?? true,
                    fov: context.value(for: "fov")?.angleValue,
                    width: context.value(for: "width")?.doubleValue,
                    height: context.value(for: "height")?.doubleValue
                )),
                in: context
            ))
        },
        "export": .block(.init(.node, [
            "file": .string,
            "camera": .string,
            "background": .colorOrTexture,
            "width": .number,
            "height": .number,
            "zUp": .boolean,
        ], .mesh, .void)) { context in
            context.exports.append(Export(
                name: context.name,
                file: context.value(for: "file")?.stringValue ?? "",
                geometry: context.children.compactMap { $0.value as? Geometry },
                camera: context.value(for: "camera")?.stringValue,
                background: context.value(for: "background")?.colorOrTextureValue,
                width: context.value(for: "width")?.doubleValue,
                height: context.value(for: "height")?.doubleValue,
                zUp: context.value(for: "zUp")?.boolValue
            ))
            return .void
        },
        "background": .property(.colorOrTexture, { parameter, context in
            context.background = MaterialProperty(parameter.value)
        }, { context in
            .colorOrTexture(context.background ?? .color(.clear))
        }),
    ])

    static let global: Symbols = _merge(functions, colors, meshes, paths)
    static let node: Symbols = _merge(transform, name, background)
    static let shape: Symbols = _merge(node, detail, smoothing, material)
    static let group: Symbols = _merge(shape, childTransform, font)
    static let user: Symbols = _merge(shape, font)
    static let builder: Symbols = group
    static let hull: Symbols = _merge(group, points)
    static let polygon: Symbols = _merge(transform, childTransform, points, color)
    static let mesh: Symbols = _merge(node, smoothing, color, childTransform, polygons)
    static let pathShape: Symbols = _merge(transform, detail, color, background)
    static let path: Symbols = _merge(pathShape, childTransform, font, pathPoints)
    static let definition: Symbols = _merge(root, pathPoints)
    static let all: Symbols = _merge(definition, shape, path)
}

extension EvaluationContext {
    var paths: [Path] {
        children.compactMap { $0.value as? Path }
    }
}

extension Geometry {
    convenience init(type: GeometryType, in context: EvaluationContext) {
        self.init(
            type: type,
            name: context.name,
            transform: context.transform,
            material: context.material,
            smoothing: context.smoothing,
            children: context.children.compactMap { $0.value as? Geometry },
            sourceLocation: context.sourceLocation
        )
    }
}

private func _merge(_ symbols: Symbols...) -> Symbols {
    var result = Symbols()
    for symbols in symbols {
        result.merge(symbols) { $1 }
    }
    return result
}
