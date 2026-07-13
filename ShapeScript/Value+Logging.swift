//
//  Value+Logging.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 17/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public protocol Loggable {
    /// Top-level log description
    var logDescription: String { get }
    /// Log description when nested inside an array or tuple
    var nestedLogDescription: String { get }
}

public extension String {
    init(logDescriptionFor value: Any) {
        self.init(describing: (value as? Loggable)?.logDescription ?? value)
    }

    init(nestedLogDescriptionFor value: Any) {
        self.init(describing: (value as? Loggable)?.nestedLogDescription ?? value)
    }
}

extension String: Loggable {
    public var logDescription: String {
        self
    }

    public var nestedLogDescription: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

extension TextValue: Loggable {
    var logDescription: String {
        string
    }

    var nestedLogDescription: String {
        string.nestedLogDescription
    }
}

extension Double: Loggable {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = false
        formatter.positiveInfinitySymbol = "∞"
        formatter.negativeInfinitySymbol = "-∞"
        formatter.notANumberSymbol = "NaN"
        return formatter
    }()

    public var logDescription: String {
        let result = Self.formatter.string(from: self as NSNumber) ?? "NaN"
        return result == "-0" ? "0" : result
    }

    public var nestedLogDescription: String {
        logDescription
    }
}

extension Bool: Loggable {
    public var logDescription: String {
        "\(self)"
    }

    public var nestedLogDescription: String {
        logDescription
    }
}

extension Vector: Loggable {
    public var logDescription: String {
        "\(x.logDescription) \(y.logDescription) \(z.logDescription)"
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Angle: Loggable {
    public var logDescription: String {
        halfturns.logDescription
    }

    public var nestedLogDescription: String {
        logDescription
    }
}

extension Rotation: Loggable {
    public var logDescription: String {
        "\(roll.logDescription) \(yaw.logDescription) \(pitch.logDescription)"
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Color: Loggable {
    public var logDescription: String {
        var components = components
        if a == 1 {
            components.removeLast()
        }
        return components.map(\.logDescription).joined(separator: " ")
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Texture: Loggable {
    public var logDescription: String {
        guard let url else {
            return "texture { #data }"
        }
        return url.path.logDescription
    }

    public var nestedLogDescription: String {
        guard let url else {
            return "texture"
        }
        return url.path.nestedLogDescription
    }
}

extension MaterialProperty: Loggable {
    public var logDescription: String {
        switch self {
        case let .color(color):
            color.logDescription
        case let .texture(texture):
            texture.logDescription
        }
    }

    public var nestedLogDescription: String {
        switch self {
        case let .color(color):
            color.nestedLogDescription
        case let .texture(texture):
            texture.nestedLogDescription
        }
    }
}

extension Material: Loggable {
    public var logDescription: String {
        let fields = [
            opacity.map { "opacity \(Value.numberOrTexture($0).logDescription)" },
            color.map { "color \($0.logDescription)" },
            texture.map { "texture \($0.logDescription)" },
            metallicity.map { "metallicity \(Value.numberOrTexture($0).logDescription)" },
            roughness.map { "roughness \(Value.numberOrTexture($0).logDescription)" },
            glow.map { "glow \($0.logDescription)" },
        ].compactMap { $0 }

        switch fields.count {
        case 0:
            return "material { default }"
        case 1:
            return "material { \(fields[0]) }"
        default:
            return "material {\n    \(fields.joined(separator: "\n    "))\n}"
        }
    }

    public var nestedLogDescription: String {
        "material"
    }
}

extension Path: Loggable {
    public var logDescription: String {
        if subpaths.count > 1 {
            return "path { subpaths \(subpaths.count) }"
        }
        return "path { points \(points.count) }"
    }

    public var nestedLogDescription: String {
        "path"
    }
}

extension Polygon: Loggable {
    public var logDescription: String {
        "polygon { points \(vertices.count) }"
    }

    public var nestedLogDescription: String {
        "polygon"
    }
}

extension PathPoint: Loggable {
    public var logDescription: String {
        "\(nestedLogDescription) { \(position.logDescription) }"
    }

    public var nestedLogDescription: String {
        isCurved ? "curve" : "point"
    }
}

extension Bounds: Loggable {
    public var logDescription: String {
        """
        bounds {
            min \(min.logDescription)
            max \(max.logDescription)
        }
        """
    }

    public var nestedLogDescription: String {
        "bounds"
    }
}

extension GeometryType: Loggable {
    public var logDescription: String {
        switch self {
        case .group: "group"
        case .cone: "cone"
        case .cylinder: "cylinder"
        case .sphere: "sphere"
        case .cube: "cube"
        case .extrude: "extrusion"
        case .lathe: "lathe"
        case .loft: "loft"
        case .fill: "fill"
        case .hull: "hull"
        case .minkowski: "minkowski"
        case .union: "union"
        case .difference: "difference"
        case .intersection: "intersection"
        case .xor: "xor"
        case .stencil: "stencil"
        case .path: "path"
        case .mesh: "mesh"
        case .camera: "camera"
        case .light: "light"
        }
    }

    public var nestedLogDescription: String {
        logDescription
    }
}

extension Geometry: Loggable {
    public var logDescription: String {
        let epsilon = 0.0001
        let scale = transform.scale
        let scaleDescription: String? = if abs(scale.x - scale.y) < epsilon, abs(scale.y - scale.z) < epsilon {
            abs(scale.x - 1) < epsilon ? nil : "size \(scale.x.logDescription)"
        } else {
            "size \(scale.logDescription)"
        }

        var fields = [
            name.flatMap { $0.isEmpty ? nil : "name \($0.nestedLogDescription)" },
            childCount == 0 ? nil : "children \(childCount)",
            scaleDescription,
            transform.translation == .zero ? nil : "position \(transform.translation.logDescription)",
            transform.rotation == .identity ? nil : "orientation \(transform.rotation.logDescription)",
        ].compactMap { $0 }

        switch type {
        case let .camera(camera):
            if let fov = camera.fov, abs(fov.degrees - 60) > epsilon {
                fields.append("fov \(fov.logDescription)")
            }
            if let width = camera.width {
                fields.append("width \(width.logDescription)")
            }
            if let height = camera.height {
                fields.append("height \(height.logDescription)")
            }
            switch camera.background {
            case let .color(color)?:
                fields.append("background \(color.logDescription)")
            case let .texture(texture)?:
                fields.append("background \(texture.nestedLogDescription)")
            case nil:
                break
            }
        case let .light(light):
            if light.color != .white {
                fields.append("color \(light.color.logDescription)")
            }
            fields.append("spread \(light.spread.logDescription)")
            if light.penumbra != 1 {
                fields.append("penumbra \(light.penumbra.logDescription)")
            }
            if light.shadowOpacity != 0 {
                fields.append("shadow \(light.shadowOpacity.logDescription)")
            }
        case .mesh:
            fields.append("polygons \(polygons { false }.count)")
        case let .path(path):
            if path.subpaths.count > 1 {
                fields.append("subpaths \(path.subpaths.count)")
            } else {
                fields.append("points \(path.points.count)")
            }
        default:
            break
        }

        let block = switch fields.count {
        case 0:
            ""
        case 1:
            " { \(fields[0]) }"
        default:
            " {\n    \(fields.joined(separator: "\n    "))\n}"
        }
        return type.logDescription + block
    }

    public var nestedLogDescription: String {
        type.nestedLogDescription
    }
}

extension Optional: Loggable {
    public var logDescription: String {
        map { String(logDescriptionFor: $0) } ?? "nil"
    }

    public var nestedLogDescription: String {
        map { String(nestedLogDescriptionFor: $0) } ?? "nil"
    }
}

extension Array: Loggable {
    public var logDescription: String {
        if count == 1 {
            return String(logDescriptionFor: self[0])
        }
        return map { String(nestedLogDescriptionFor: $0) }.joined(separator: " ")
    }

    public var nestedLogDescription: String {
        "(\(map { String(nestedLogDescriptionFor: $0) }.joined(separator: " ")))"
    }
}

extension Dictionary: Loggable where Key == String {
    public var logDescription: String {
        let fields = map { "\($0.key) \(String(nestedLogDescriptionFor: $0.value))" }
        switch fields.count {
        case 0:
            return "object {}"
        case 1:
            return "object { \(fields[0]) }"
        default:
            return "object {\n    \(fields.sorted().joined(separator: "\n    "))\n}"
        }
    }

    public var nestedLogDescription: String {
        "object"
    }
}

extension RangeValue: Loggable {
    public var logDescription: String {
        let stepText = step.map { " step \($0.logDescription)" } ?? ""
        guard let end else {
            return "from \(start.logDescription)\(stepText)"
        }
        return "\(start.logDescription) to \(end.logDescription)\(stepText)"
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Value: Loggable {
    private var loggableValue: Loggable {
        // Note: this switch is technically not needed, but serves to
        // ensure logging conformance is not forgotten for new types
        switch self {
        case let .color(color): color
        case let .texture(texture): texture
        case let .material(material): material
        case let .boolean(boolean): boolean
        case let .number(number): number
        case let .radians(radians): radians
        case let .halfturns(halfturns): halfturns
        case let .vector(vector): vector
        case let .size(size): size
        case let .rotation(rotation): rotation
        case let .string(string): string
        case let .font(font): font
        case let .text(text): text
        case let .path(path): path
        case let .mesh(mesh): mesh
        case let .polygon(polygon): polygon
        case let .point(point): point
        case let .tuple(tuple): tuple
        case let .range(range): range
        case let .bounds(bounds): bounds
        case let .object(object): object
        case let .pretransformed(values): values
        }
    }

    public var logDescription: String {
        loggableValue.logDescription
    }

    public var nestedLogDescription: String {
        loggableValue.nestedLogDescription
    }
}
