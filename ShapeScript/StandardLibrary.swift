//
//  StandardLibrary.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 18/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension Dictionary where Key == String, Value == Symbol {
    static func + (lhs: Symbols, rhs: Symbols) -> Symbols {
        lhs.merging(rhs) { $1 }
    }

    static let transform: Symbols = [
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
    ]

    static let childTransform: Symbols = [
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
            context.material.color = parameter.value as? Color
        }, { context in
            .color(context.material.color ?? .white)
        }),
        "colour": .property(.color, { parameter, context in
            context.material.color = parameter.value as? Color
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
        "extrude": .block(.custom(.builder, ["along": .paths])) { context in
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

    static let camera: Symbols = [
        "camera": .block(.custom(nil, [
            "position": .vector,
            "orientation": .rotation,
            "size": .size,
            "fov": .number,
        ])) { context in
            var hasPosition = false, hasOrientation = false, hasScale = false
            if let position = context.value(for: "position")?.value as? Vector {
                context.transform.offset = position
                hasPosition = true
            }
            if let orientation = context.value(for: "orientation")?.value as? Rotation {
                context.transform.rotation = orientation
                hasOrientation = true
            }
            if let size = context.value(for: "size")?.value as? Vector {
                context.transform.scale = size
                hasScale = true
            }
            return .mesh(Geometry(
                type: .camera(Camera(
                    hasPosition: hasPosition,
                    hasOrientation: hasOrientation,
                    hasScale: hasScale,
                    fov: (context.value(for: "fov")?.doubleValue).map {
                        Angle(radians: $0 * .pi)
                    }
                )),
                in: context
            ))
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
        "text": .block(.text) { context in
            let width = context.value(for: "wrapwidth")?.doubleValue
            let text = context.children.map { $0.textValue }
            let paths = Path.text(text, width: width, detail: context.detail / 8)
            return .tuple(paths.map { .path($0.transformed(by: context.transform)) })
        },
        "svgpath": .block(.text) { context in
            let text = context.children.map { $0.stringValue }.joined(separator: "\n")
            let svgPath: SVGPath
            do {
                svgPath = try SVGPath(text)
            } catch let error as SVGErrorType {
                throw RuntimeErrorType.assertionFailure(error.message)
            }
            return .path(Path(
                svgPath,
                detail: context.detail / 8,
                color: context.material.color
            ).transformed(by: context.transform))
        },
    ]

    static let points: Symbols = [
        // vertices
        "point": .command(.vector) { parameter, context in
            .point(.point(
                parameter.value as! Vector,
                color: context.material.color
            ))
        },
        "curve": .command(.vector) { parameter, context in
            .point(.curve(
                parameter.value as! Vector,
                color: context.material.color
            ))
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

    static let global: Symbols = _merge(functions, colors, meshes, paths, [
        "detail": .property(.number, { parameter, context in
            // TODO: throw error if min/max detail level exceeded
            context.detail = Swift.max(0, parameter.intValue)
        }, { context in
            .number(Double(context.detail))
        }),
        "smoothing": .property(.number, { parameter, context in
            // TODO: find a better way to represent null/auto
            let angle = Swift.min(.pi, parameter.doubleValue * .pi)
            context.smoothing = angle < 0 ? nil : .radians(angle)
        }, { context in
            .number((context.smoothing?.radians).map { $0 / .pi } ?? -1)
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
        "assert": .command(.boolean) { value, _ in
            if !value.boolValue {
                throw RuntimeErrorType.assertionFailure("")
            }
            return .void
        },
    ])

    static let node: Symbols = _merge(global, transform, [
        "name": .property(.string, { parameter, context in
            context.name = parameter.stringValue
        }, { context in
            .string(context.name)
        }),
    ])

    static let root: Symbols = _merge(global, material, childTransform, background, camera)
    static let shape: Symbols = _merge(node, material)
    static let builder: Symbols = _merge(shape, childTransform)
    static let group: Symbols = _merge(shape, childTransform)
    static let path: Symbols = _merge(global, childTransform, points, color)
    static let pathShape: Symbols = _merge(global, transform, color)
    static let text: Symbols = _merge(global, transform, color)
    static let definition: Symbols = root
    static let all: Symbols = _merge(root, shape, points)
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
