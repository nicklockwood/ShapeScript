//
//  Geometry+CSGImport.swift
//  ShapeScript
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

// MARK: Public interface

public struct CSGImportError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public let line: Int
    public let column: Int

    public var errorDescription: String? {
        "\(message) (line \(line), column \(column))"
    }
}

public extension Geometry {
    /// Imports an evaluated OpenSCAD CSG tree, not a SCAD program.
    convenience init(csgString: String, isCancelled: @escaping CancellationHandler) throws {
        if isCancelled() {
            throw CancellationError()
        }
        var parser = CSGParser(csgString, isCancelled: isCancelled)
        let nodes = try parser.parse()
        let importer = CSGImporter(isCancelled: isCancelled)
        let shapes = try nodes.map { try importer.shape($0, material: .default) }
        try importer.checkCancellation()
        if !shapes.isEmpty, shapes.allSatisfy({ $0.paths != nil }),
           !shapes
           .contains(where: { $0.geometry.childDebug || $0.geometry.childIsFocused || $0.geometry.childIsHidden })
        {
            self.init(
                type: .path(Path(subpaths: shapes.flatMap { $0.paths ?? [] })),
                name: nil, transform: .identity, material: .default,
                smoothing: .zero, children: [], sourceLocation: nil
            )
            return
        }
        self.init(
            type: .group, name: nil, transform: .identity, material: .default,
            smoothing: .zero, children: shapes.map(\.geometry), sourceLocation: nil
        )
    }
}

public extension Scene {
    /// Creates a scene from an evaluated OpenSCAD CSG tree.
    /// If a source file URL is supplied, its size is checked against the text file limit.
    convenience init(
        csgString: String,
        at fileURL: URL? = nil,
        cache: GeometryCache? = nil,
        isCancelled: @escaping CancellationHandler
    ) throws {
        if isCancelled() {
            throw CancellationError()
        }
        if let fileURL {
            try fileURL.validateFileSize(limit: FileSizeLimit.text)
        }
        let geometry = try Geometry(csgString: csgString, isCancelled: isCancelled)
        self.init(background: .color(.clear), children: [geometry], cache: cache)
    }
}

// MARK: Implementation

private enum CSGValue {
    case number(Double), boolean(Bool), string(String), array([CSGValue]), undefined

    var numbers: [Double]? {
        guard case let .array(values) = self else {
            return nil
        }
        let numbers = values.compactMap { value -> Double? in
            if case let .number(number) = value {
                return number
            }
            return nil
        }
        return numbers.count == values.count ? numbers : nil
    }
}

private enum CSGModifier: Character {
    case debug = "#", background = "%", focus = "!", hide = "*"
}

private struct CSGNode {
    let name: String
    let arguments: [String: CSGValue]
    let children: [CSGNode]
    let line: Int
    let column: Int
    var modifiers: Set<CSGModifier> = []

    func error(_ message: String) -> CSGImportError {
        .init(message: message, line: line, column: column)
    }

    func validate(_ names: [String], positional: [String] = []) throws -> [String: CSGValue] {
        var result = arguments
        for (index, name) in positional.enumerated() {
            if let value = result.removeValue(forKey: "\(index)") {
                guard result[name] == nil else {
                    throw error("Duplicate CSG argument '\(name)'")
                }
                result[name] = value
            }
        }
        if let unknown = result.keys.sorted().first(where: { !names.contains($0) }) {
            throw error("Unsupported CSG argument '\(unknown)' for '\(name)'")
        }
        return result
    }

    func number(_ values: [String: CSGValue], _ name: String, default fallback: Double) throws -> Double {
        guard let value = values[name] else {
            return fallback
        }
        guard case let .number(number) = value else {
            throw error("CSG argument '\(name)' must be a number")
        }
        return number
    }

    func boolean(_ values: [String: CSGValue], _ name: String, default fallback: Bool) throws -> Bool {
        guard let value = values[name] else {
            return fallback
        }
        guard case let .boolean(boolean) = value else {
            throw error("CSG argument '\(name)' must be a boolean")
        }
        return boolean
    }

    func string(_ values: [String: CSGValue], _ name: String, default fallback: String) throws -> String {
        guard let value = values[name] else {
            return fallback
        }
        guard case let .string(string) = value else {
            throw error("CSG argument '\(name)' must be a string")
        }
        return string
    }

    func vector(_ value: CSGValue?, count: Int, scalar: Bool = false) throws -> [Double] {
        if scalar, case let .number(number)? = value {
            return Array(repeating: number, count: count)
        }
        guard let numbers = value?.numbers, numbers.count == count else {
            throw error("Expected a CSG vector with \(count) components")
        }
        return numbers
    }
}

// MARK: Parsing

private struct CSGParser {
    private enum Token {
        case identifier(String)
        case number(Double)
        case string(String)
        case symbol(Character)
        case eof
    }

    private let source: String
    private var characters: Substring
    private let isCancelled: CancellationHandler
    private var characterCount = 0
    private var line = 1, column = 1
    private var tokenLine = 1, tokenColumn = 1
    private var token: Token = .eof

    init(_ input: String, isCancelled: @escaping CancellationHandler) {
        self.source = input
        self.characters = Substring(input)
        self.isCancelled = isCancelled
    }

    mutating func parse() throws -> [CSGNode] {
        try readToken()
        var nodes = [CSGNode]()
        while !isEnd {
            try nodes.append(readNode(depth: 0))
        }
        return nodes
    }

    private var isEnd: Bool {
        if case .eof = token {
            return true
        }
        return false
    }

    private func matches(_ symbol: Character) -> Bool {
        if case .symbol(symbol) = token {
            return true
        }
        return false
    }

    private func error(_ message: String) -> CSGImportError {
        .init(message: message, line: tokenLine, column: tokenColumn)
    }

    private mutating func requireToken(_ symbol: Character) throws {
        guard matches(symbol) else {
            throw error("Expected '\(symbol)' in CSG input")
        }
        try readToken()
    }

    private mutating func readNode(depth: Int) throws -> CSGNode {
        guard depth < 256 else {
            throw error("CSG nesting is too deep")
        }
        var modifiers = Set<CSGModifier>()
        while case let .symbol(character) = token, let modifier = CSGModifier(rawValue: character) {
            modifiers.insert(modifier)
            try readToken()
        }
        guard case let .identifier(name) = token else {
            throw error("Expected a CSG operation")
        }
        let line = tokenLine, column = tokenColumn
        try readToken()
        try requireToken("(")
        var arguments = [String: CSGValue]()
        var position = 0
        while !matches(")") {
            let key: String
            if case let .identifier(name) = token, !["true", "false", "undef"].contains(name) {
                key = name
                try readToken()
                try requireToken("=")
            } else {
                key = "\(position)"
                position += 1
            }
            guard arguments[key] == nil else {
                throw error("Duplicate CSG argument '\(key)'")
            }
            arguments[key] = try readValue(depth: 0)
            if !matches(",") {
                break
            }
            try readToken()
        }
        try requireToken(")")
        var children = [CSGNode]()
        if matches("{") {
            try readToken()
            while !matches("}") {
                guard !isEnd else {
                    throw error("Unterminated CSG block")
                }
                try children.append(readNode(depth: depth + 1))
            }
            try readToken()
            if matches(";") {
                try readToken()
            }
        } else if matches(";") {
            try readToken()
        } else {
            try children.append(readNode(depth: depth + 1))
        }
        return .init(
            name: name, arguments: arguments, children: children,
            line: line, column: column, modifiers: modifiers
        )
    }

    private mutating func readValue(depth: Int) throws -> CSGValue {
        guard depth < 256 else {
            throw error("CSG array nesting is too deep")
        }
        switch token {
        case let .number(number):
            try readToken()
            return .number(number)
        case let .string(string):
            try readToken()
            return .string(string)
        case let .identifier(name):
            switch name {
            case "true":
                try readToken()
                return .boolean(true)
            case "false":
                try readToken()
                return .boolean(false)
            case "undef":
                try readToken()
                return .undefined
            default:
                throw error("Unsupported CSG value '\(name)'")
            }
        case .symbol("["):
            try readToken()
            var values = [CSGValue]()
            while !matches("]") {
                try values.append(readValue(depth: depth + 1))
                if !matches(",") {
                    break
                }
                try readToken()
            }
            try requireToken("]")
            return .array(values)
        case .symbol, .eof:
            throw error("Expected a CSG value")
        }
    }

    private var character: Character? {
        characters.first
    }

    private mutating func readCharacter() throws {
        if characterCount.isMultiple(of: 1024), isCancelled() {
            throw CancellationError()
        }
        if characters.popFirst()?.isNewline == true {
            line += 1
            column = 1
        } else {
            column += 1
        }
        characterCount += 1
    }

    private mutating func readToken() throws {
        if isCancelled() {
            throw CancellationError()
        }
        while let character {
            if character.isWhitespace {
                try readCharacter()
                continue
            }
            if character == "/" {
                if characters.dropFirst().first == "/" {
                    while let c = self.character, !c.isNewline {
                        try readCharacter()
                    }
                    continue
                }
                if characters.dropFirst().first == "*" {
                    tokenLine = line
                    tokenColumn = column
                    try readCharacter()
                    try readCharacter()
                    while !(self.character == "*" && characters.dropFirst().first == "/") {
                        guard self.character != nil else {
                            throw error("Unterminated CSG comment")
                        }
                        try readCharacter()
                    }
                    try readCharacter()
                    try readCharacter()
                    continue
                }
            }
            break
        }
        tokenLine = line
        tokenColumn = column
        guard let character else {
            token = .eof
            return
        }
        if character.isLetter || character == "_" || character == "$" {
            let start = characters.startIndex
            while let c = self.character, c.isLetter || c.isNumber || c == "_" || c == "$" {
                try readCharacter()
            }
            token = .identifier(String(source[start ..< characters.startIndex]))
        } else if character.isNumber || character == "-" || character == "+" || character == "." {
            let start = characters.startIndex
            while let c = self.character, "0123456789.eE+-".contains(c) {
                try readCharacter()
            }
            guard let number = Double(source[start ..< characters.startIndex]), number.isFinite else {
                throw error("Invalid or non-finite CSG number")
            }
            token = .number(number)
        } else if character == "\"" {
            let start = characters.startIndex
            try readCharacter()
            while self.character != "\"" {
                guard self.character != nil else {
                    throw error("Unterminated CSG string")
                }
                if self.character == "\\" {
                    try readCharacter()
                    guard self.character != nil else {
                        throw error("Unterminated CSG string")
                    }
                }
                try readCharacter()
            }
            try readCharacter()
            guard let string = try? JSONDecoder().decode(
                String.self,
                from: Data(source[start ..< characters.startIndex].utf8)
            ) else {
                throw error("Invalid CSG string escape")
            }
            token = .string(string)
        } else if "(){}[]=,;#%!*".contains(character) {
            token = .symbol(character)
            try readCharacter()
        } else {
            throw error("Unsupported CSG token '\(character)'")
        }
    }
}

// MARK: Geometry conversion

private struct CSGShape {
    let geometry: Geometry
    let paths: [Path]?
}

private struct CSGImporter {
    let isCancelled: CancellationHandler

    func checkCancellation() throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

    private func geometry(
        _ type: GeometryType,
        material: Material,
        children: [Geometry] = [],
        transform: Transform = .identity
    ) -> Geometry {
        .init(
            type: type,
            name: nil,
            transform: transform,
            material: material,
            smoothing: .zero,
            children: children,
            sourceLocation: nil
        )
    }

    private func result(_ mesh: Mesh, material: Material) throws -> CSGShape {
        let geometry = geometry(.mesh(mesh), material: material)
        // Raw meshes must be ready even when a boolean's preview skips its cutters.
        guard geometry.build(isCancelled) else {
            throw CancellationError()
        }
        return .init(geometry: geometry, paths: nil)
    }

    private func result(_ paths: [Path], material: Material) -> CSGShape {
        let paths = paths.map { $0.materialToVertexColors(material: material) }
        return .init(
            geometry: geometry(
                .group,
                material: material,
                children: paths.map { geometry(.path($0), material: material) }
            ),
            paths: paths
        )
    }

    private func children(_ node: CSGNode, material: Material) throws -> [CSGShape] {
        try node.children.map { try shape($0, material: material) }
    }

    private func paths(_ children: [CSGShape], node: CSGNode) throws -> [Path] {
        guard children.allSatisfy({ $0.paths != nil }) else {
            throw node.error("'\(node.name)' requires 2D children")
        }
        return children.filter { !$0.geometry.isHidden }.flatMap { $0.paths ?? [] }
    }

    private func fragments(_ values: [String: CSGValue], radius: Double, node: CSGNode) throws -> Int {
        let fn = try node.number(values, "$fn", default: 0)
        let fa = try node.number(values, "$fa", default: 12)
        let fs = try node.number(values, "$fs", default: 2)
        guard fn >= 0, fa > 0, fs > 0 else {
            throw node.error("Invalid CSG tessellation parameters")
        }
        let count = fn > 0 ? max(3, fn.rounded(.down)) : max(5, ceil(min(360 / fa, abs(radius) * 2 * .pi / fs)))
        guard let count = Int(exactly: count),
              count <= 100_000
        else {
            throw node.error("CSG tessellation is too large")
        }
        return count
    }

    func shape(_ node: CSGNode, material: Material) throws -> CSGShape {
        let shape = try unmodifiedShape(node, material: material)
        for modifier in node.modifiers {
            switch modifier {
            case .debug:
                shape.geometry.debug = true
            case .focus:
                shape.geometry.isFocused = true
            case .background, .hide:
                shape.geometry.isHidden = true
            }
        }
        return shape
    }

    private func unmodifiedShape(_ node: CSGNode, material: Material) throws -> CSGShape {
        try checkCancellation()
        let tessellation = ["$fn", "$fa", "$fs", "convexity"]
        switch node.name {
        case "group", "union", "difference", "intersection", "hull", "minkowski", "render":
            _ = try node.validate(node.name == "render" ? ["convexity"] : [])
            let children = try children(node, material: material)
            if !children.isEmpty, children.allSatisfy({ $0.paths != nil }) {
                guard node.name == "group" || node.name == "render" || children.count == 1 else {
                    throw node.error("2D '\(node.name)' is not supported by the CSG importer")
                }
                return try .init(
                    geometry: geometry(.group, material: material, children: children.map(\.geometry)),
                    paths: paths(children, node: node)
                )
            }
            guard children.allSatisfy({ $0.paths == nil }) else {
                throw node.error("Mixed 2D and 3D CSG children are unsupported")
            }
            let type: GeometryType
            switch node.name {
            case "group", "render":
                type = .group
            case "union":
                type = .union
            case "difference":
                type = .difference
            case "intersection":
                type = .intersection
            case "hull":
                type = .hull([])
            case "minkowski":
                type = .minkowski
            default:
                throw node.error("Unsupported CSG operation '\(node.name)'")
            }
            return .init(geometry: geometry(type, material: material, children: children.map(\.geometry)), paths: nil)
        case "color":
            let values = try node.validate(["c", "alpha"], positional: ["c", "alpha"])
            let components: [Double]
            if let numbers = values["c"]?.numbers, numbers.count == 3 || numbers.count == 4 {
                components = numbers
            } else {
                throw node.error("CSG colors must be RGB or RGBA vectors")
            }
            let alpha = try node.number(values, "alpha", default: components.count == 4 ? components[3] : 1)
            guard components.allSatisfy({ (0 ... 1).contains($0) }), (0 ... 1).contains(alpha) else {
                throw node.error("Invalid CSG color")
            }
            return try shape(
                .init(name: "group", arguments: [:], children: node.children, line: node.line, column: node.column),
                material: Material(color: Color(
                    red: components[0],
                    green: components[1],
                    blue: components[2],
                    alpha: alpha
                ))
            )
        case "cube", "square":
            guard node.children.isEmpty else {
                throw node.error("CSG primitives cannot have children")
            }
            let values = try node.validate(["size", "center"], positional: ["size", "center"])
            let count = node.name == "cube" ? 3 : 2
            let size = try node.vector(values["size"] ?? .number(1), count: count, scalar: true)
            guard size.allSatisfy({ $0 > 0 }) else {
                throw node.error("CSG size must be positive")
            }
            let center = try node.boolean(values, "center", default: false)
            if count == 2 {
                var path = Path.rectangle(width: size[0], height: size[1], color: material.color)
                if !center {
                    path = path.translated(by: Vector(size[0] / 2, size[1] / 2))
                }
                return result([path], material: material)
            }
            let scale = Vector(size[0], size[1], size[2])
            return .init(
                geometry: geometry(.cube, material: material, transform: .init(
                    scale: scale,
                    translation: center ? .zero : scale / 2
                )),
                paths: nil
            )
        case "sphere", "circle", "cylinder":
            guard node.children.isEmpty else {
                throw node.error("CSG primitives cannot have children")
            }
            let names = node.name == "cylinder" ? ["h", "r", "r1", "r2", "d", "d1", "d2", "center"] : ["r", "d"]
            let values = try node.validate(
                names + tessellation,
                positional: node.name == "cylinder" ? ["h", "r1", "r2", "center"] : ["r"]
            )
            let radius = try values["d"].map { _ in try node.number(values, "d", default: 2) / 2 } ?? node.number(
                values,
                "r",
                default: 1
            )
            let r1 = try values["d1"].map { _ in try node.number(values, "d1", default: 2) / 2 } ?? node.number(
                values,
                "r1",
                default: radius
            )
            let r2 = try values["d2"].map { _ in try node.number(values, "d2", default: 2) / 2 } ?? node.number(
                values,
                "r2",
                default: radius
            )
            guard radius >= 0, r1 >= 0, r2 >= 0 else {
                throw node.error("CSG radii cannot be negative")
            }
            let detail = try fragments(values, radius: node.name == "cylinder" ? max(r1, r2) : radius, node: node)
            if node.name == "circle" {
                return result(
                    [.circle(radius: radius, segments: detail, color: material.color)],
                    material: material
                )
            }
            let axis = Rotation(from: .unitY, to: .unitZ)
            if node.name == "sphere" {
                guard detail <= 1024 else {
                    throw node.error("CSG sphere tessellation is too large")
                }
                if radius == 0 {
                    return try result(.empty, material: material)
                }
                return .init(
                    geometry: geometry(.sphere(segments: detail), material: material, transform: .init(
                        scale: Vector(radius * 2, radius * 2, radius * 2),
                        rotation: axis
                    )),
                    paths: nil
                )
            }
            let height = try node.number(values, "h", default: 1)
            guard height > 0 else {
                throw node.error("CSG cylinder height must be positive")
            }
            let center = try node.boolean(values, "center", default: false)
            let profile = Path([
                .point(0, -height / 2),
                .point(r1, -height / 2),
                .point(r2, height / 2),
                .point(0, height / 2),
            ])
            let mesh = Mesh.lathe(profile, slices: detail, material: material, isCancelled: isCancelled)
                .rotated(by: axis).translated(by: center ? .zero : Vector(
                    0,
                    0,
                    height / 2
                ))
            try checkCancellation()
            return try result(mesh, material: material)
        case "polygon", "polyhedron":
            guard node.children.isEmpty else {
                throw node.error("CSG primitives cannot have children")
            }
            let names = node.name == "polygon" ? ["points", "paths", "convexity"] : [
                "points",
                "faces",
                "triangles",
                "convexity",
            ]
            let values = try node.validate(names, positional: ["points", node.name == "polygon" ? "paths" : "faces"])
            guard case let .array(pointValues)? = values["points"] else {
                throw node.error("CSG points must be an array")
            }
            let points = try pointValues.map { value -> Vector in
                let p = try node.vector(value, count: node.name == "polygon" ? 2 : 3)
                return Vector(p[0], p[1], p.count == 3 ? p[2] : 0)
            }
            let indices: [[Int]]
            var indicesValue = values[node.name == "polygon" ? "paths" : "faces"] ?? values["triangles"]
            if case .undefined? = indicesValue {
                indicesValue = nil
            }
            if let indicesValue {
                guard case let .array(faces) = indicesValue else {
                    throw node.error("CSG indices must be an array")
                }
                indices = try faces.map { face in
                    guard let numbers = face.numbers, numbers.count >= 3 else {
                        throw node.error("Invalid CSG face")
                    }
                    return try numbers.map { number in
                        guard let index = Int(exactly: number), points.indices.contains(index) else {
                            throw node.error("CSG point index is out of bounds")
                        }
                        return index
                    }
                }
            } else if node.name == "polygon" {
                indices = [Array(points.indices)]
            } else {
                throw node.error("CSG polyhedron is missing faces")
            }
            if node.name == "polygon" {
                let paths = indices.map { face -> Path in
                    let p = face.map { PathPoint.point(points[$0]) }
                    return Path(p + p.prefix(1))
                }
                return result([Path(subpaths: paths)], material: material)
            }
            let polygons = try indices.map { face -> Polygon in
                // OpenSCAD polyhedron faces use clockwise winding viewed from outside.
                guard let polygon = Polygon(face.reversed().map { points[$0] }, material: material) else {
                    throw node.error("Degenerate or nonplanar CSG face")
                }
                return polygon
            }
            return try result(Mesh(polygons), material: material)
        case "offset":
            let values = try node.validate(["r", "delta", "chamfer"] + tessellation)
            guard values["r"] == nil, values["delta"] != nil,
                  try !node.boolean(values, "chamfer", default: false)
            else {
                throw node.error("Rounded or chamfered CSG offsets are not supported")
            }
            let profiles = try paths(children(node, material: material), node: node)
            guard profiles.count == 1 else {
                throw node.error("CSG offset requires a single profile")
            }
            let delta = try node.number(values, "delta", default: 0)
            let paths = profiles.map { $0.inset(by: -delta, isCancelled: isCancelled) }
            try checkCancellation()
            return result(paths, material: material)
        case "linear_extrude", "rotate_extrude":
            let names = node.name == "linear_extrude" ? ["height", "center", "twist", "slices", "scale"] : [
                "angle",
                "start",
            ]
            let values = try node.validate(
                names + tessellation,
                positional: node.name == "linear_extrude" ? ["height"] : []
            )
            // OpenSCAD's extrusion operators project 2D children onto the XY plane.
            let profiles = try paths(children(node, material: material), node: node).map { path in
                let projected = Path(subpaths: path.subpaths.map { subpath in
                    Path(subpath.points.map { .point(Vector($0.position.x, $0.position.y), color: $0.color) })
                })
                return projected.faceNormal.z < 0 ? projected.inverted() : projected
            }
            if node.name == "linear_extrude" {
                if let scale = values["scale"] {
                    let components = try node.vector(scale, count: 2, scalar: true)
                    guard components == [1, 1] else {
                        throw node.error("Tapered CSG linear_extrude is not supported")
                    }
                }
                let height = try node.number(values, "height", default: 1)
                guard height > 0 else {
                    throw node.error("CSG extrusion height must be positive")
                }
                let twist = try node.number(values, "twist", default: 0)
                let detail = try fragments(values, radius: 1, node: node)
                // Straight extrusions need only one section, regardless of $fn/$fa/$fs.
                let defaultSlices = twist == 0 ? 1 : max(Double(detail), ceil(abs(twist) / 15))
                let slices = try node.number(values, "slices", default: defaultSlices)
                guard let sections = Int(exactly: slices), sections > 0, sections <= 100_000 else {
                    throw node.error("Invalid CSG extrusion slices")
                }
                let center = try node.boolean(values, "center", default: false)
                guard profiles.reduce(0, { $0 + $1.points.count }) <= 1_000_000 / sections else {
                    throw node.error("CSG extrusion tessellation is too large")
                }
                let mesh = Mesh.extrude(
                    profiles,
                    depth: height,
                    twist: .degrees(twist),
                    sections: sections,
                    material: material,
                    isCancelled: isCancelled
                )
                .translated(by: center ? .zero : Vector(0, 0, height / 2))
                try checkCancellation()
                return try result(mesh, material: material)
            }
            guard try node.number(values, "angle", default: 360) == 360,
                  try node.number(values, "start", default: 0) == 0
            else {
                throw node.error("Partial CSG rotate_extrude is not supported")
            }
            let radius = profiles.flatMap(\.points).map { abs($0.position.x) }.max() ?? 0
            let detail = try fragments(values, radius: radius, node: node)
            let mesh = Mesh.union(
                profiles.map { Mesh.lathe($0, slices: detail, material: material, isCancelled: isCancelled) },
                isCancelled: isCancelled
            )
            .rotated(by: Rotation(from: .unitY, to: .unitZ))
            try checkCancellation()
            return try result(mesh, material: material)
        case "text":
            guard node.children.isEmpty else {
                throw node.error("CSG primitives cannot have children")
            }
            let values = try node.validate(
                ["text", "size", "font", "halign", "valign", "spacing", "direction", "language", "script"] +
                    tessellation,
                positional: ["text", "size", "font"]
            )
            guard try node.string(values, "halign", default: "left") == "left",
                  try node.string(values, "valign", default: "baseline") == "baseline",
                  try node.string(values, "direction", default: "ltr") == "ltr",
                  try node.string(values, "language", default: "en") == "en",
                  try node.string(values, "script", default: "Latn") == "Latn",
                  try node.number(values, "spacing", default: 1) == 1
            else {
                throw node.error("Unsupported CSG text layout options")
            }
            #if canImport(CoreText)
            let text = try node.string(values, "text", default: "")
            let font = try node.string(values, "font", default: "Liberation Sans")
            guard !font.contains(":") else {
                throw node.error("OpenSCAD font style descriptors are not supported")
            }
            let size = try node.number(values, "size", default: 10)
            guard size > 0 else {
                throw node.error("CSG text size must be positive")
            }
            let detail = try fragments(values, radius: size, node: node)
            let paths = TextPath(
                text: [TextValue(string: text, font: font, color: material.color)],
                wrapWidth: nil,
                detail: max(1, detail / 8),
                isCancelled: isCancelled
            ).paths.scaled(by: size)
            try checkCancellation()
            return result(paths, material: material)
            #else
            throw node.error("CSG text requires platform font support")
            #endif
        case "translate", "scale", "rotate", "mirror", "multmatrix":
            return try transformed(node, material: material)
        default:
            throw node.error("Unsupported CSG operation '\(node.name)'")
        }
    }

    private func transformed(_ node: CSGNode, material: Material) throws -> CSGShape {
        let matrix: [[Double]]
        switch node.name {
        case "multmatrix":
            let values = try node.validate(["m"], positional: ["m"])
            guard case let .array(rows)? = values["m"], rows.count == 4 else {
                throw node.error("CSG multmatrix requires a 4×4 matrix")
            }
            matrix = try rows.map { try node.vector($0, count: 4) }
            guard matrix[3] == [0, 0, 0, 1] else {
                throw node.error("Projective CSG matrices are unsupported")
            }
        case "translate", "scale":
            let values = try node.validate(["v"], positional: ["v"])
            let v = try node.vector(values["v"], count: 3, scalar: node.name == "scale")
            if node.name == "translate" {
                matrix = [
                    [1, 0, 0, v[0]],
                    [0, 1, 0, v[1]],
                    [0, 0, 1, v[2]],
                    [0, 0, 0, 1],
                ]
            } else {
                matrix = [
                    [v[0], 0, 0, 0],
                    [0, v[1], 0, 0],
                    [0, 0, v[2], 0],
                    [0, 0, 0, 1],
                ]
            }
        case "mirror":
            let values = try node.validate(["v"], positional: ["v"])
            let v = try node.vector(values["v"], count: 3)
            let normal = Vector(v[0], v[1], v[2])
            guard normal.length > 0, normal.length.isFinite else {
                throw node.error("Invalid CSG mirror normal")
            }
            let n = normal.normalized().components
            var reflection = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
            for i in 0 ..< 3 {
                for j in 0 ..< 3 {
                    let identity: Double = i == j ? 1 : 0
                    let projection: Double = 2 * n[i] * n[j]
                    reflection[i][j] = identity - projection
                }
            }
            reflection[3][3] = 1
            matrix = reflection
        case "rotate":
            let values = try node.validate(["a", "v"], positional: ["a", "v"])
            if let angles = values["a"]?.numbers {
                guard angles.count == 3, values["v"] == nil else {
                    throw node.error("Invalid CSG Euler rotation")
                }
                let x = angles[0] * .pi / 180, y = angles[1] * .pi / 180, z = angles[2] * .pi / 180
                let cx = cos(x), sx = sin(x), cy = cos(y), sy = sin(y), cz = cos(z), sz = sin(z)
                matrix = [
                    [cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx, 0],
                    [sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx, 0],
                    [-sy, cy * sx, cy * cx, 0],
                    [0, 0, 0, 1],
                ]
            } else {
                let angle = try node.number(values, "a", default: 0) * .pi / 180
                let v = try node.vector(values["v"] ?? .array([.number(0), .number(0), .number(1)]), count: 3)
                let normal = Vector(v[0], v[1], v[2])
                guard normal.length > 0, normal.length.isFinite else {
                    throw node.error("Invalid CSG rotation axis")
                }
                let n = normal.normalized(), c = cos(angle), s = sin(angle), t = 1 - c
                matrix = [
                    [t * n.x * n.x + c, t * n.x * n.y - s * n.z, t * n.x * n.z + s * n.y, 0],
                    [t * n.x * n.y + s * n.z, t * n.y * n.y + c, t * n.y * n.z - s * n.x, 0],
                    [t * n.x * n.z - s * n.y, t * n.y * n.z + s * n.x, t * n.z * n.z + c, 0],
                    [0, 0, 0, 1],
                ]
            }
        default:
            throw node.error("Unsupported CSG transform '\(node.name)'")
        }
        func apply(_ p: Vector) throws -> Vector {
            let coordinates = matrix.prefix(3).map { $0[0] * p.x + $0[1] * p.y + $0[2] * p.z + $0[3] }
            guard coordinates.allSatisfy(\.isFinite) else {
                throw node.error("CSG transform overflow")
            }
            return Vector(coordinates[0], coordinates[1], coordinates[2])
        }
        let shapes = try children(node, material: material)
        let hasModifiers = shapes.contains {
            $0.geometry.childDebug || $0.geometry.childIsFocused || $0.geometry.childIsHidden
        }
        let determinant = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) - matrix[0][1] *
            (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) + matrix[0][2] *
            (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])

        // Baking an entire subtree into one mesh would discard nested debug, hide, and focus flags.
        func transformedGeometry(_ source: Geometry) throws -> Geometry {
            try checkCancellation()
            let type: GeometryType
            var children = [Geometry]()
            var transform = Transform.identity
            switch source.type {
            case .group, .union, .difference, .intersection, .xor, .stencil, .hull, .minkowski:
                type = source.type
                children = try source.children.map(transformedGeometry)
                if type == .minkowski {
                    // A translation applies once to the sum, not once per operand.
                    let origin = try apply(source.worldTransform.translation)
                    transform = .translation(origin * Double(1 - source.visibleChildren.count))
                }
            case let .path(path):
                let path = path.transformed(by: source.worldTransform)
                type = try .path(Path(subpaths: path.subpaths.map { subpath in
                    try Path(subpath.points.map { point in
                        var point = point
                        point.position = try apply(point.position)
                        return point
                    })
                }))
            case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square, .text,
                 .extrude, .lathe, .loft, .fill, .mesh, .camera, .light:
                let unmodified = geometry(source.type, material: source.material, transform: source.worldTransform)
                guard unmodified.build(isCancelled) else {
                    throw CancellationError()
                }
                let polygons = try unmodified.merged(isCancelled).polygons.map { polygon -> Polygon in
                    try checkCancellation()
                    let vertices = try polygon.vertices.map {
                        try Vertex(apply($0.position), texcoord: $0.texcoord, color: $0.color)
                    }
                    guard let polygon = Polygon(
                        determinant < 0 ? Array(vertices.reversed()) : vertices,
                        material: polygon.material
                    ) else {
                        throw node.error("Degenerate CSG transform")
                    }
                    return polygon
                }
                type = .mesh(Mesh(polygons))
            }
            let geometry = Geometry(
                type: type, name: nil, transform: transform, material: source.material,
                smoothing: .zero, children: children, sourceLocation: nil
            )
            if case .mesh = type, !geometry.build(isCancelled) {
                throw CancellationError()
            }
            geometry.debug = source.debug
            geometry.isFocused = source.isFocused
            geometry.isHidden = source.isHidden
            return geometry
        }
        if shapes.allSatisfy({ $0.paths != nil }) {
            let paths = try paths(shapes, node: node).map { path in
                try Path(subpaths: path.subpaths.map { subpath in
                    try Path(subpath.points.map { point in try .point(apply(point.position), color: point.color) })
                })
            }
            if hasModifiers {
                return try .init(
                    geometry: geometry(.group, material: material, children: shapes.map {
                        try transformedGeometry($0.geometry)
                    }),
                    paths: paths
                )
            }
            return result(paths, material: material)
        }
        guard shapes.allSatisfy({ $0.paths == nil }) else {
            throw node.error("Mixed 2D and 3D CSG children are unsupported")
        }
        guard determinant.isFinite, abs(determinant) > Double.ulpOfOne else {
            throw node.error("Singular CSG transforms are unsupported")
        }
        if hasModifiers {
            return try .init(
                geometry: geometry(.group, material: material, children: shapes.map {
                    try transformedGeometry($0.geometry)
                }),
                paths: nil
            )
        }
        let polygons = try shapes.flatMap { shape -> [Polygon] in
            guard shape.geometry.build(isCancelled) else {
                throw CancellationError()
            }
            return try shape.geometry.merged(isCancelled).polygons.map { polygon in
                try checkCancellation()
                let vertices = try polygon.vertices.map {
                    try Vertex(apply($0.position), texcoord: $0.texcoord, color: $0.color)
                }
                guard let result = Polygon(
                    determinant < 0 ? Array(vertices.reversed()) : vertices,
                    material: polygon.material
                ) else {
                    throw node.error("Degenerate CSG transform")
                }
                return result
            }
        }
        try checkCancellation()
        return try result(Mesh(polygons), material: material)
    }
}
