//
//  StandardLibrary.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 18/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

extension Dictionary where Key == String, Value == Symbol {
    static func + (lhs: Symbols, rhs: Symbols) -> Symbols {
        lhs.merging(rhs) { $1 }
    }

    static let transforms: Symbols = [
        "translate": .command(.vector) { parameter, context in
            let vector = parameter.value as! Vector
            context.childTransform.translate(by: vector)
            return .void
        },
        "rotate": .command(.rotation) { parameter, context in
            let rotation = parameter.value as! Rotation
            context.childTransform.rotate(by: rotation)
            return .void
        },
        "scale": .command(.size) { parameter, context in
            let scale = parameter.value as! Vector
            context.childTransform.scale(by: scale)
            return .void
        },
    ]

    static let background: Symbols = [
        "background": .property(.colorOrTexture, { parameter, context in
            context.background = MaterialProperty(parameter.value) ?? .color(.clear)
        }, { context in
            .colorOrTexture(context.background)
        }),
    ]

    static let color: Symbols = [
        "color": .property(.color, { parameter, context in
            context.material.color = parameter.value as? Color
        }, { context in
            .color(context.material.color ?? .white)
        }),
        "colour": .property(.color, { parameter, context in
            context.material.color = parameter.value as? Color
        }, { context in
            .color(context.material.color ?? .white)
        }),
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

    static let materials: Symbols = color + [
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
        "cone": .block(.primitive) { context in
            .mesh(Geometry(type: .cone(segments: context.detail), in: context))
        },
        "cylinder": .block(.primitive) { context in
            .mesh(Geometry(type: .cylinder(segments: context.detail), in: context))
        },
        "sphere": .block(.primitive) { context in
            .mesh(Geometry(type: .sphere(segments: context.detail), in: context))
        },
        "cube": .block(.primitive) { context in
            .mesh(Geometry(type: .cube, in: context))
        },
        // container
        "group": .block(.group) { context in
            .mesh(Geometry(type: .group, in: context))
        },
        // builders
        "extrude": .block(.custom(.builder, ["along": .paths])) { context in
            let along = context.value(for: "along")?.value as? [Path] ?? []
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
                default:
                    preconditionFailure()
                }
            }
            endPath()
            if subpaths.count != 1 {
                subpaths = [Path(subpaths: subpaths)]
            }
            return .path(subpaths[0].transformed(by: context.transform))
        },
        "circle": .block(.primitive) { context in
            .path(Path.circle(segments: context.detail).transformed(by: context.transform))
        },
        "square": .block(.primitive) { context in
            .path(Path.square().transformed(by: context.transform))
        },
        "roundrect": .block(.custom(.primitive, ["radius": .number])) { context in
            #if canImport(CoreGraphics)
            let radius = context.value(for: "radius")?.doubleValue ?? 0.25
            return .path(Path(
                cgPath: CGPath(
                    roundedRect: CGRect(x: -0.5, y: -0.5, width: 1, height: 1),
                    cornerWidth: CGFloat(radius),
                    cornerHeight: CGFloat(radius),
                    transform: nil
                ),
                detail: context.detail
            ).transformed(by: context.transform))
            #else
            // TODO: throw error when CoreGraphics not available
            return .path(Path.square().transformed(by: context.transform))
            #endif
        },
        "text": .block(.text) { context in
            let width = context.value(for: "wrapwidth")?.doubleValue
            let linespacing = context.value(for: "linespacing")?.doubleValue
            let text = context.children.compactMap { $0.stringValue }.joined(separator: "\n")
            let paths = Path.text(
                text,
                font: context.font,
                width: width,
                linespacing: linespacing,
                detail: context.detail / 8
            )
            return .tuple(paths.map { .path($0.transformed(by: context.transform)) })
        },
        "svgpath": .block(.text) { context in
            #if canImport(CoreGraphics)
            let text = context.children.compactMap { $0.stringValue }.joined(separator: "\n")
            do {
                let cgPath = try CGPath.fromSVG(text)
                let path = Path(cgPath: cgPath, detail: context.detail / 8)
                return .path(path.transformed(by: context.transform))
            } catch let error as SVGErrorType {
                throw RuntimeErrorType.assertionFailure(error.message)
            }
            #else
            throw RuntimeErrorType
                .assertionFailure("The svgpath command is not available on this platform")
            #endif
        },
    ]

    static let points: Symbols = [
        // vertices
        "point": .command(.vector) { parameter, _ in
            .point(.point(parameter.value as! Vector))
        },
        "curve": .command(.vector) { parameter, _ in
            .point(.curve(parameter.value as! Vector))
        },
    ]

    static let functions: Symbols = [
        "true": .constant(.boolean(true)),
        "false": .constant(.boolean(false)),
        "not": .command(.boolean) { value, _ in
            .boolean(!value.boolValue)
        },
        // Math functions
        "rnd": .command(.void) { _, context in
            .number(context.random.next())
        },
        "seed": .property(.number, { value, context in
            context.random = RandomSequence(seed: value.doubleValue)
        }, { context in
            .number(Double(context.random.seed))
        }),
        "round": .command(.number) { value, _ in
            .number(value.doubleValue.rounded())
        },
        "floor": .command(.number) { value, _ in
            .number(value.doubleValue.rounded(.down))
        },
        "ceil": .command(.number) { value, _ in
            .number(value.doubleValue.rounded(.up))
        },
        "max": .command(.pair) { value, _ in
            let values = value.value as! [Double]
            return .number(values.max()!)
        },
        "min": .command(.pair) { value, _ in
            let values = value.value as! [Double]
            return .number(values.min()!)
        },
        "abs": .command(.number) { value, _ in
            .number(value.doubleValue.magnitude)
        },
        "sqrt": .command(.number) { value, _ in
            .number(sqrt(value.doubleValue))
        },
        "pow": .command(.pair) { value, _ in
            let values = value.value as! [Double]
            return .number(pow(values[0], values[1]))
        },
        "cos": .command(.number) { value, _ in
            .number(cos(value.doubleValue))
        },
        "acos": .command(.number) { value, _ in
            .number(acos(value.doubleValue))
        },
        "sin": .command(.number) { value, _ in
            .number(sin(value.doubleValue))
        },
        "asin": .command(.number) { value, _ in
            .number(asin(value.doubleValue))
        },
        "tan": .command(.number) { value, _ in
            .number(tan(value.doubleValue))
        },
        "atan": .command(.number) { value, _ in
            .number(atan(value.doubleValue))
        },
        "atan2": .command(.pair) { value, _ in
            let values = value.value as! [Double]
            return .number(atan2(values[0], values[1]))
        },
        "pi": .constant(.number(.pi)),
    ]

    static let global: Symbols = _merge(functions, meshes, paths, [
        "detail": .property(.number, { parameter, context in
            // TODO: throw error if min/max detail level exceeded
            context.detail = Swift.max(0, parameter.intValue)
        }, { context in
            .number(Double(context.detail))
        }),
        // TODO: is here the right place for this?
        "font": .property(.font, { parameter, context in
            context.font = parameter.stringValue
        }, { context in
            .string(context.font)
        }),
        // Debug
        "print": .command(.tuple) { value, context in
            context.debugLog(value.tupleValue)
            return .void
        },
    ])

    static let primitive: Symbols = _merge(global, materials, [
        "name": .property(.string, { parameter, context in
            context.name = parameter.stringValue
        }, { context in
            .string(context.name)
        }),
        "position": .property(.vector, { parameter, context in
            context.transform.offset = parameter.value as! Vector
        }, { context in
            .vector(context.transform.offset)
        }),
        "orientation": .property(.rotation, { parameter, context in
            context.transform.rotation = parameter.value as! Rotation
        }, { context in
            .rotation(context.transform.rotation)
        }),
        "size": .property(.size, { parameter, context in
            context.transform.scale = parameter.value as! Vector
        }, { context in
            .size(context.transform.scale)
        }),
    ])

    static let root: Symbols = _merge(global, background, materials, transforms)
    static let builder: Symbols = _merge(primitive, transforms)
    static let group: Symbols = _merge(primitive, transforms)
    static let path: Symbols = _merge(global, transforms, points)
    static let text: Symbols = primitive
    static let definition: Symbols = root
    static let all: Symbols = _merge(root, primitive, points)
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
