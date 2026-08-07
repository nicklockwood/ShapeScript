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
        switch symbol.setter {
        case let .block(type, _):
            keys.formUnion(type.options.keys)
        case .function, .property, .constant, .option, .placeholder:
            break
        }
    }
    return keys
}()

extension Symbols {
    static func + (lhs: Symbols, rhs: Symbols) -> Symbols {
        lhs.merging(rhs) { $1 }
    }

    static let transform: Symbols = [
        "position": .property(.vector, { parameter, context in
            context.state.transform.translation = parameter.vectorValue
        }, { context in
            .vector(context.state.transform.translation)
        }),
        "orientation": .property(.rotation, { parameter, context in
            context.state.transform.rotation = parameter.rotationValue
        }, { context in
            .rotation(context.state.transform.rotation)
        }),
        "size": .property(.size, { parameter, context in
            context.state.transform.scale = parameter.vectorValue
        }, { context in
            .size(context.state.transform.scale)
        }),
    ]

    static let childTransform: Symbols = [
        "translate": .command(.vector) { parameter, context in
            let vector = parameter.vectorValue
            context.state.childTransform.translate(by: vector)
        },
        "rotate": .command(.rotation) { parameter, context in
            let rotation = parameter.rotationValue
            context.state.childTransform.rotate(by: rotation)
        },
        "scale": .command(.size) { parameter, context in
            let scale = parameter.vectorValue
            context.state.childTransform.scale(by: scale)
        },
    ]

    static let colors: Symbols = [
        "rgb": .function(.list(.number), .color) { value, _ in
            let values = value.doublesValue
            guard values.count >= 3 else {
                throw RuntimeErrorType.missingArgument(for: "", index: values.count, type: .number)
            }
            guard values.count <= 4 else {
                throw RuntimeErrorType.unexpectedArgument(for: "", max: 4)
            }
            return .color(Color(
                red: values[0],
                green: values[1],
                blue: values[2],
                alpha: values.count > 3 ? values[3] : 1
            ))
        },
        "hsb": .function(.list(.number), .color) { value, _ in
            let values = value.doublesValue
            guard values.count >= 3 else {
                throw RuntimeErrorType.missingArgument(for: "", index: values.count, type: .number)
            }
            guard values.count <= 4 else {
                throw RuntimeErrorType.unexpectedArgument(for: "", max: 4)
            }
            return .color(Color(
                hue: values[0],
                saturation: values[1],
                brightness: values[2],
                alpha: values.count > 3 ? values[3] : 1
            ))
        },
        "white": .constant(.color(.white)),
        "black": .constant(.color(.black)),
        "gray": .constant(.color(.gray)),
        "red": .constant(.color(.red)),
        "green": .constant(.color(.green)),
        "blue": .constant(.color(.blue)),
        "yellow": .constant(.color(.yellow)),
        "cyan": .constant(.color(.cyan)),
        "magenta": .constant(.color(.magenta)),
        "orange": .constant(.color(.orange)),
        "purple": .constant(.color(.purple)),
    ]

    static let textures: Symbols = [
        "checkerboard": .constant(.texture(.checkerboard)),
    ]

    static let color: Symbols = colors + [
        "color": .property(.color, { parameter, context in
            context.state.material.albedo = parameter.colorOrTextureValue
        }, { context in
            .color(context.state.material.color ?? .white)
        }),
    ]

    static let material: Symbols = color + textures + [
        "opacity": .property(.numberOrTexture, { parameter, context in
            switch parameter {
            case let .number(opacity):
                let opacity = opacity * context.state.opacity
                context.state.material.opacity = .color(.init(white: opacity, alpha: opacity))
            case let .texture(texture):
                guard let texture else { fallthrough }
                let opacity = texture.intensity * context.state.opacity
                context.state.material.opacity = .texture(texture.withIntensity(opacity))
            default:
                let opacity = context.state.opacity
                context.state.material.opacity = .color(.init(white: opacity, alpha: opacity))
            }
        }, { context in
            switch context.state.material.opacity ?? .color(.white) {
            case let .color(color):
                return .number(color.alpha / context.state.opacity)
            case let .texture(texture):
                let opacity = texture.intensity / context.state.opacity
                return .texture(texture.withIntensity(opacity))
            }
        }),
        "texture": .property(.texture, { parameter, context in
            context.state.material.albedo = parameter.colorOrTextureValue
        }, { context in
            .texture(context.state.material.texture)
        }),
        "normals": .property(.texture, { parameter, context in
            context.state.material.normals = parameter.value as? Texture
        }, { context in
            .texture(context.state.material.normals)
        }),
        "metallicity": .property(.numberOrTexture, { parameter, context in
            context.state.material.metallicity = parameter.numberOrTextureValue
        }, { context in
            .numberOrTexture(context.state.material.metallicity ?? .color(.black))
        }),
        "roughness": .property(.numberOrTexture, { parameter, context in
            context.state.material.roughness = parameter.numberOrTextureValue
        }, { context in
            .numberOrTexture(context.state.material.roughness ?? .color(.black))
        }),
        "glow": .property(.colorOrTexture, { parameter, context in
            context.state.material.glow = parameter.colorOrTextureValue
        }, { context in
            .colorOrTexture(context.state.material.glow ?? .color(.black))
        }),
        "material": .property(.material, { parameter, context in
            context.state.material = parameter.value as? Material ?? .default
        }, { context in
            .material(context.state.material)
        }),
    ]

    static let polygons: Symbols = [
        "polygon": .block(.init(.polygon, [:], .point, .list(.polygon))) { context in
            let path = Path(context.state.children.compactMap {
                $0.value as? PathPoint
            }).transformed(by: context.state.transform)
            let polygons = path.closed().facePolygons(material: context.state.material)
            return .tuple(polygons.map { .polygon($0) })
        },
    ]

    static let meshes: Symbols = [
        // primitives
        "cone": .block(.shape) { context in
            .mesh(Geometry(type: .cone(segments: context.state.detail), in: context))
        },
        "cylinder": .block(.shape) { context in
            .mesh(Geometry(type: .cylinder(segments: context.state.detail), in: context))
        },
        "icosphere": .block(.shape) { context in
            let subdivisions = Int(log2(Double(Swift.max(4, context.state.detail))).rounded()) - 2
            return .mesh(Geometry(type: .icosphere(subdivisions: subdivisions), in: context))
        },
        "sphere": .block(.shape) { context in
            .mesh(Geometry(type: .sphere(segments: context.state.detail), in: context))
        },
        "cube": .block(.shape) { context in
            .mesh(Geometry(type: .cube, in: context))
        },
        // container
        "group": .block(.group) { context in
            .mesh(Geometry(type: .group, in: context))
        },
        // builders
        "extrude": .block(.init(_merge(.builder, miterLimit), [
            "along": .list(.path),
            "twist": .halfturns,
            "axisAligned": .boolean,
            "miterLimit": .number,
        ], .path, .list(.mesh))) { context in
            let twist = context.value(for: "twist")?.angleValue ?? .zero
            let miterLimit = (context.value(for: "miterLimit")?.doubleValue)
                .map(MiterLimit.ratio) ?? context.state.miterLimit
            let align: Path.Alignment = context.value(for: "axisAligned").map {
                $0.boolValue ? .axis : .tangent
            } ?? .default
            if let along = context.value(for: "along")?.tupleValue as? [Path] {
                // shapes follow a common path
                return .mesh(Geometry(type: .extrude(context.paths, .init(
                    along: along.map { $0.withDetail(context.state.detail, forTwist: twist) },
                    twist: twist,
                    align: align,
                    miterLimit: miterLimit
                )), in: context))
            }
            if twist == .zero {
                // Fast path - can reuse meshes (good for text)
                return .mesh(Geometry(
                    type: .extrude(context.paths, .default),
                    in: context
                ))
            }
            // Slow path, each calculated separately, no reuse
            return .tuple(context.paths.map {
                let vector = $0.faceNormal / 2
                let along = Path.line(-vector, vector)
                    .withDetail(context.state.detail, forTwist: twist)
                return .mesh(Geometry(type: .extrude([$0], .init(
                    along: [along],
                    twist: twist,
                    align: align,
                    miterLimit: nil
                )), in: context))
            })
        },
        "lathe": .block(.builder) { context in
            .mesh(Geometry(
                type: .lathe(context.paths, segments: context.state.detail),
                in: context
            ))
        },
        "loft": .block(.builder) { context in
            .mesh(Geometry(type: .loft(context.paths), in: context))
        },
        "fill": .block(.builder) { context in
            .mesh(Geometry(type: .fill(context.paths), in: context))
        },
        "hull": .block(.hull) { context in
            let vertices = try context.state.children.flatMap { child -> [Vertex] in
                switch child {
                case let .point(point):
                    return [Vertex(point)]
                case let .path(path):
                    return path.subpaths.flatMap(\.edgeVertices)
                case .mesh:
                    return []
                default:
                    throw RuntimeErrorType.assertionFailure(
                        "Unexpected child of type \(child.type) in hull"
                    )
                }
            }
            return .mesh(Geometry(type: .hull(vertices), in: context))
        },
        "minkowski": .block(.minkowski) { context in
            .mesh(Geometry(type: .minkowski, in: context))
        },
        // mesh
        "mesh": .block(.mesh) { context in
            let polygons = context.state.children.compactMap { $0.value as? Polygon }
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
            position.map { context.state.transform.translation = $0 }
            let orientation = context.value(for: "orientation")?.value as? Rotation
            orientation.map { context.state.transform.rotation = $0 }
            return .mesh(Geometry(
                type: .light(Light(
                    position: position,
                    orientation: orientation,
                    color: context.value(for: "color")?.colorValue ?? Light.default.color,
                    spread: context.value(for: "spread")?.angleValue ?? Light.default.spread,
                    penumbra: context.value(for: "penumbra")?.doubleValue ?? Light.default.penumbra,
                    shadowOpacity: context.value(for: "shadow")?.doubleValue ?? Light.default.shadowOpacity
                )),
                in: context
            ))
        },
        // debug
        "debug": .block(.group) { context in
            for case let .mesh(geometry) in context.state.children {
                geometry.debug = true
            }
            if context.state.children.count == 1,
               case let .mesh(child) = context.state.children[0]
            {
                return .mesh(child)
            }
            return .tuple(context.state.children)
        },
        // focus
        "focus": .block(.group) { context in
            for case let .mesh(geometry) in context.state.children {
                geometry.isFocused = true
            }
            if context.state.children.count == 1,
               case let .mesh(child) = context.state.children[0]
            {
                return .mesh(child)
            }
            return .tuple(context.state.children)
        },
    ]

    static let paths: Symbols = [
        "path": .block(.path) { context in
            var subpaths = [Path]()
            var points = [PathPoint]()
            func endPath() {
                if !points.isEmpty {
                    subpaths.append(.curve(points, detail: context.state.detail / 4))
                }
                points.removeAll()
            }
            for i in context.state.children.indices {
                let child = context.state.children[i]
                switch child {
                case let .point(point):
                    points.append(point)
                case let .path(path):
                    if !path.isClosed, let point = path.points.first, !points.isEmpty {
                        points.append(point.curved(false))
                    }
                    endPath()
                    subpaths.append(path)
                    if !path.isClosed, context.state.children.indices.contains(i + 1), {
                        switch context.state.children[i + 1] {
                        case .point: true
                        case let .path(path): !path.isClosed
                        default: false
                        }
                    }(), let point = path.points.last {
                        points.append(point.curved(false))
                    }
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
            return .path(subpaths[0].transformed(by: context.state.transform))
        },
        "arc": .block(.init(.polygon, [
            "angle": .halfturns,
        ], .void, .list(.point))) { context in
            let angle = context.value(for: "angle")?.angleValue ?? .pi
            let span = Swift.max(0, Swift.min(1, abs(angle.radians) / (2 * .pi)))
            var segments = Int(ceil(span * Double(context.state.detail)))
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
                color: context.state.material.color,
                isCancelled: context.isCancelled
            ).transformed(by: context.state.transform))
        },
        "circle": .block(.pathShape) { context in
            .mesh(Geometry(type: .circle(segments: context.state.detail), in: context))
        },
        "square": .block(.pathShape) { context in
            .mesh(Geometry(type: .square, in: context))
        },
        "polygon": .block(.init(.polygon, [
            "sides": .number,
        ], .optional(.point), .union([.path, .list(.polygon)]))) { context in
            let sides = context.value(for: "sides")?.intValue
            let points = context.state.children.compactMap { $0.value as? PathPoint }
            if !points.isEmpty {
                if sides != nil {
                    throw RuntimeErrorType.assertionFailure("Polygon cannot have both sides and points")
                }
                let path = Path(points).transformed(by: context.state.transform)
                let polygons = path.closed().facePolygons(material: context.state.material)
                return .tuple(polygons.map { .polygon($0) })
            }
            return .path(Path.polygon(
                sides: sides ?? 5,
                color: context.state.material.color
            ).transformed(by: context.state.transform))
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
                detail: context.state.detail / 4,
                color: context.state.material.color
            ).transformed(by: context.state.transform))
        },
        "text": .block(.init(.pathShape, [
            "font": .font,
            "wrapwidth": .number,
            "linespacing": .number,
        ], .text, .list(.path))) { context in
            let width = context.value(for: "wrapwidth")?.doubleValue
            let text = context.state.children.compactMap { $0.value as? TextValue }
            let paths = Path.text(text, width: width, detail: context.state.detail / 8)
            return .tuple(paths.map { .path($0.transformed(by: context.state.transform)) })
        },
        "svgpath": .block(.init(.pathShape, [:], .string, .path)) { context in
            let text = context.state.children.map(\.stringValue).joined(separator: "\n")
            let svgPath: SVGPath
            do {
                svgPath = try SVGPath(string: text)
            } catch let error as SVGError {
                throw RuntimeErrorType.assertionFailure(error.message)
            }
            return .path(Path(
                svgPath,
                detail: context.state.detail / 4,
                color: context.state.material.color
            ).transformed(by: context.state.transform))
        },
        "inset": .function(
            .tuple([.list(.union([.path, .mesh])), .number]),
            .union([.path, .mesh])
        ) { value, context in
            guard case let .tuple(values) = value else { preconditionFailure() }
            let inset = values[1].doubleValue
            func process(_ value: ShapeScript.Value) -> [ShapeScript.Value] {
                switch value {
                case let .path(path):
                    return [.path(path.inset(by: inset).transformed(by: context.state.transform))]
                case let .mesh(geometry):
                    let geometry = geometry.insetByRewritingPrimitives(
                        by: inset,
                        sourceLocation: context.sourceLocation
                    )
                    return [.mesh(geometry.transformed(by: context.state.transform))]
                case let .tuple(values):
                    return values.flatMap(process)
                default:
                    return []
                }
            }
            let results = process(values[0])
            return results.count == 1 ? results[0] : .tuple(results)
        },
    ]

    static let points: Symbols = [
        "point": .function(.point, .point) { parameter, context in
            var point = parameter.value as! PathPoint
            point.color = point.color ?? context.state.material.color
            return .point(point)
        },
    ]

    static let pathPoints: Symbols = _merge(points, [
        "curve": .command(.point) { parameter, context in
            var point = parameter.value as! PathPoint
            point.color = point.color ?? context.state.material.color
            point.isCurved = true
            try context.addValue(.point(point))
        },
    ])

    static let functions: Symbols = [
        // Debug
        "print": .command(.list(.any)) { value, context in
            context.debugLog(value.tupleValue)
        },
        "assert": .command(.tuple([.boolean, .optional(.string)])) { value, _ in
            let values = value.tupleValue
            if values[0] as? Bool == false {
                throw RuntimeErrorType.assertionFailure(
                    values.count == 2 ? values[1] as? String ?? "" : ""
                )
            }
        },
        // Logic
        "true": .constant(.boolean(true)),
        "false": .constant(.boolean(false)),
        "not": .function(.boolean, .boolean) { value, _ in
            .boolean(!value.boolValue)
        },
        // Unbounded range
        "from": .function(.number, .range) { value, _ in
            .range(.init(from: value.doubleValue, to: nil))
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
            case 0: .number(0)
            case ..<0: .number(-1)
            default: .number(1)
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
        "sum": .function(.list(.list(.number)), .list(.number)) { value, _ in
            let values = value.tupleValue as! [[Double]]
            if values.count == 1 {
                return .number(values[0].reduce(0, +))
            }
            // Vector sum
            var columns = values.reduce(0) { Swift.max($0, $1.count) }
            var sums = [Double](repeating: 0, count: columns)
            for vector in values {
                for i in vector.indices {
                    sums[i] += vector[i]
                }
            }
            return sums.isEmpty ? 0 : .tuple(sums.map { .number($0) })
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
        "pi": .constant(.radians(.pi)),
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
            let strings = stringValues.map(\.stringValue)
            return .string(strings.joined(separator: separator))
        },
        "trim": .function(.string, .string) { value, _ in
            .string(value.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ))
        },
        // Fonts
        "fonts": .function(.void, .list(.string)) { _, context in
            .tuple(context.fontNames.map { .string($0) })
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
            context.state.name = parameter.stringValue
        }, { context in
            .string(context.state.name)
        }),
    ]

    static let background: Symbols = [
        "background": .getter(.colorOrTexture) { context in
            .colorOrTexture(context.background ?? .color(.clear))
        },
    ]

    static let font: Symbols = [
        "font": .property(.font, { parameter, context in
            context.state.font = parameter.stringValue
        }, { context in
            .font(context.state.font)
        }),
    ]

    static let detail: Symbols = [
        "detail": .property(.number, { parameter, context in
            // TODO: throw error if min/max detail level exceeded
            context.state.detail = Swift.max(0, parameter.intValue)
        }, { context in
            .number(Double(context.state.detail))
        }),
    ]

    static let smoothing: Symbols = [
        "smoothing": .property(.halfturns, { parameter, context in
            // TODO: find a better way to represent null/auto
            let angle = Swift.min(.pi, parameter.angleValue ?? .zero)
            context.state.smoothing = angle < .zero ? nil : angle
        }, { context in
            .halfturns(context.state.smoothing.map(\.halfturns) ?? -1)
        }),
    ]

    static let miterLimit: Symbols = [
        "miterLimit": .property(.number, { parameter, context in
            context.state.miterLimit = MiterLimit.ratio(parameter.doubleValue)
        }, { context in
            .number(context.state.miterLimit?.ratio ?? .infinity)
        }),
    ]

    static let root: Symbols = _merge(global, font, detail, smoothing, miterLimit, material, childTransform, [
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
            position.map { context.state.transform.translation = $0 }
            let orientation = context.value(for: "orientation")?.value as? Rotation
            orientation.map { context.state.transform.rotation = $0 }
            let scale = context.value(for: "size")?.value as? Vector
            scale.map { context.state.transform.scale = $0 }
            return .mesh(Geometry(
                type: .camera(Camera(
                    position: position,
                    orientation: orientation,
                    scale: scale,
                    background: context.value(for: "background")?.colorOrTextureValue,
                    antialiased: context.value(for: "antialiased")?.boolValue ?? Camera.default.antialiased,
                    fov: context.value(for: "fov")?.angleValue,
                    width: context.value(for: "width")?.doubleValue,
                    height: context.value(for: "height")?.doubleValue
                )),
                in: context
            ))
        },
        "background": .property(.colorOrTexture, { parameter, context in
            context.background = MaterialProperty(parameter.value)
        }, { context in
            .colorOrTexture(context.background ?? .color(.clear))
        }),
    ])

    static let global: Symbols = _merge(functions, colors, textures, meshes, paths, points)
    static let node: Symbols = _merge(transform, name, background)
    static let shape: Symbols = _merge(node, detail, smoothing, material)
    static let group: Symbols = _merge(shape, miterLimit, childTransform, font)
    static let user: Symbols = _merge(shape, miterLimit, font)
    static let builder: Symbols = _merge(shape, childTransform, font)
    static let hull: Symbols = _merge(group, points)
    static let polygon: Symbols = _merge(transform, childTransform, points, color)
    static let mesh: Symbols = _merge(node, smoothing, miterLimit, color, childTransform, polygons)
    static let pathShape: Symbols = _merge(transform, detail, color, background)
    static let path: Symbols = _merge(pathShape, childTransform, font, pathPoints)
    static let definition: Symbols = _merge(root, pathPoints)
    static let all: Symbols = _merge(definition, shape, path)
}

extension EvaluationContext {
    var paths: [Path] {
        state.children.compactMap { $0.value as? Path }
    }
}

extension Geometry {
    convenience init(type: GeometryType, in context: EvaluationContext) {
        self.init(
            type: type,
            name: context.state.name,
            transform: context.state.transform,
            material: context.state.material,
            smoothing: context.state.smoothing,
            children: context.state.children.compactMap { $0.value as? Geometry },
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
