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
        case .command, .function, .property, .constant, .placeholder:
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
            context.material.color = parameter.colorValue
        }, { context in
            .color(context.material.color ?? .white)
        }),
    ]

    static let material: Symbols = color + [
        "opacity": .property(.number, { parameter, context in
            context.material.opacity = parameter.doubleValue * context.opacity
        }, { context in
            .number(context.material.opacity / context.opacity)
        }),
        "texture": .property(.texture, { parameter, context in
            context.material.texture = parameter.value as? Texture
        }, { context in
            .texture(context.material.texture)
        }),
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
        "extrude": .block(.custom(.builder, ["along": .list(.path)])) { context in
            let along = context.value(for: "along")?.tupleValue as? [Path] ?? []
            return .mesh(Geometry(type: .extrude(context.paths, along: along), in: context))
        },
        "lathe": .block(.builder) { context in
            .mesh(Geometry(type: .lathe(context.paths, segments: context.detail), in: context))
        },
        "loft": .block(.builder) { context in
            .mesh(Geometry(type: .loft(context.paths), in: context))
        },
        "fill": .block(.builder) { context in
            .mesh(Geometry(type: .fill(context.paths), in: context))
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
        "light": .block(.custom(nil, [
            "position": .vector,
            "orientation": .rotation,
            "color": .color,
            "spread": .number,
            "penumbra": .number,
        ])) { context in
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
                    penumbra: context.value(for: "penumbra")?.doubleValue ?? 1
                )),
                in: context
            ))
        },
        // debug
        "debug": .block(.group) { context in
            context.children.forEach {
                if case let .mesh(geometry) = $0 {
                    geometry.debug = true
                }
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
                        "Unexpected child of type \(child.type.errorDescription) in path"
                    )
                }
            }
            endPath()
            if subpaths.count != 1 {
                subpaths = [Path(subpaths: subpaths)]
            }
            return .path(subpaths[0].transformed(by: context.transform))
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
        "polygon": .block(.custom(.pathShape, ["sides": .number])) { context in
            let sides = context.value(for: "sides")?.intValue ?? 5
            return .path(Path.polygon(
                sides: sides,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "roundrect": .block(.custom(.pathShape, ["radius": .number])) { context in
            let radius = context.value(for: "radius")?.doubleValue ?? 0.25
            return .path(Path.roundedRectangle(
                width: 1,
                height: 1,
                radius: radius,
                detail: context.detail,
                color: context.material.color
            ).transformed(by: context.transform))
        },
        "text": .block(.custom(.text, [
            "font": .font,
            "wrapwidth": .number,
            "linespacing": .number,
        ])) { context in
            let width = context.value(for: "wrapwidth")?.doubleValue
            let text = context.children.compactMap { $0.value as? TextValue }
            let paths = Path.text(text, width: width, detail: context.detail / 8)
            return .tuple(paths.map { .path($0.transformed(by: context.transform)) })
        },
        "svgpath": .block(.text) { context in
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
        // vertices
        "point": .function(.vector, .point) { parameter, context in
            .point(.point(
                parameter.vectorValue,
                color: context.material.color
            ))
        },
        "curve": .function(.vector, .point) { parameter, context in
            .point(.curve(
                parameter.vectorValue,
                color: context.material.color
            ))
        },
    ]

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
        // Math
        "rnd": .function(.void, .number) { _, context in
            .number(context.random.next())
        },
        "seed": .property(.number, { value, context in
            context.random = RandomSequence(seed: value.doubleValue)
        }, { context in
            .number(Double(context.random.seed))
        }),
        "round": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded())
        },
        "floor": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded(.down))
        },
        "ceil": .function(.number, .number) { value, _ in
            .number(value.doubleValue.rounded(.up))
        },
        "max": .function(.list(.number), .number) { value, _ in
            .number(value.doublesValue.max() ?? 0)
        },
        "min": .function(.list(.number), .number) { value, _ in
            .number(value.doublesValue.min() ?? 0)
        },
        "abs": .function(.number, .number) { value, _ in
            .number(value.doubleValue.magnitude)
        },
        "sqrt": .function(.number, .number) { value, _ in
            .number(sqrt(value.doubleValue))
        },
        "pow": .function(.numberPair, .number) { value, _ in
            let values = value.doublesValue
            return .number(pow(values[0], values[1]))
        },
        "cos": .function(.number, .number) { value, _ in
            .number(cos(value.doubleValue))
        },
        "acos": .function(.number, .number) { value, _ in
            .number(acos(value.doubleValue))
        },
        "sin": .function(.number, .number) { value, _ in
            .number(sin(value.doubleValue))
        },
        "asin": .function(.number, .number) { value, _ in
            .number(asin(value.doubleValue))
        },
        "tan": .function(.number, .number) { value, _ in
            .number(tan(value.doubleValue))
        },
        "atan": .function(.number, .number) { value, _ in
            .number(atan(value.doubleValue))
        },
        "atan2": .function(.numberPair, .number) { value, _ in
            let values = value.doublesValue
            return .number(atan2(values[0], values[1]))
        },
        "pi": .constant(.number(.pi)),
    ]

    static let global: Symbols = _merge(functions, colors, meshes, paths)

    static let node: Symbols = _merge(global, transform, [
        "name": .property(.string, { parameter, context in
            context.name = parameter.stringValue
        }, { context in
            .string(context.name)
        }),
    ])

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
        "smoothing": .property(.number, { parameter, context in
            // TODO: find a better way to represent null/auto
            let angle = Swift.min(.pi, parameter.angleValue)
            context.smoothing = angle < .zero ? nil : angle
        }, { context in
            context.smoothing.map { .angle($0) } ?? .number(-1)
        }),
    ]

    static let root: Symbols = _merge(global, font, detail, smoothing, material, childTransform, [
        "camera": .block(.custom(nil, [
            "position": .vector,
            "orientation": .rotation,
            "size": .size,
            "background": .colorOrTexture,
            "fov": .number,
            "width": .number,
            "height": .number,
        ])) { context in
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
                    background: context.background,
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

    static let shape: Symbols = _merge(node, detail, smoothing, material)
    static let group: Symbols = _merge(shape, childTransform, font)
    static let user: Symbols = _merge(shape, font)
    static let builder: Symbols = group
    static let pathShape: Symbols = _merge(global, transform, detail, color)
    static let path: Symbols = _merge(pathShape, childTransform, font, points)
    static let definition: Symbols = root
    static let all: Symbols = _merge(root, shape, path)
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
