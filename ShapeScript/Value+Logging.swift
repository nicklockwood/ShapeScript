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
        (radians / .pi).logDescription
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
        var components = self.components
        if a == 1 {
            components.removeLast()
        }
        return components.map { $0.logDescription }.joined(separator: " ")
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Texture: Loggable {
    public var logDescription: String {
        switch self {
        case let .file(name: _, url: url):
            return url.path.logDescription
        case .data:
            return "texture { #data }"
        }
    }

    public var nestedLogDescription: String {
        switch self {
        case let .file(name: _, url: url):
            return url.path.nestedLogDescription
        case .data:
            return logDescription
        }
    }
}

extension MaterialProperty: Loggable {
    public var logDescription: String {
        switch self {
        case let .color(color):
            return color.logDescription
        case let .texture(texture):
            return texture.logDescription
        }
    }

    public var nestedLogDescription: String {
        switch self {
        case let .color(color):
            return color.nestedLogDescription
        case let .texture(texture):
            return texture.nestedLogDescription
        }
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
        case .group: return "group"
        case .cone: return "cone"
        case .cylinder: return "cylinder"
        case .sphere: return "sphere"
        case .cube: return "cube"
        case .extrude: return "extrusion"
        case .lathe: return "lathe"
        case .loft: return "loft"
        case .fill: return "fill"
        case .hull: return "hull"
        case .union: return "union"
        case .difference: return "difference"
        case .intersection: return "intersection"
        case .xor: return "xor"
        case .stencil: return "stencil"
        case .path: return "path"
        case .mesh: return "mesh"
        case .camera: return "camera"
        case .light: return "light"
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
        let scaleDescription: String?
        if abs(scale.x - scale.y) < epsilon, abs(scale.y - scale.z) < epsilon {
            scaleDescription = abs(scale.x - 1) < epsilon ?
                nil : "size \(scale.x.logDescription)"
        } else {
            scaleDescription = "size \(scale.logDescription)"
        }

        var fields = [
            name.flatMap { $0.isEmpty ? nil : "name \($0.nestedLogDescription)" },
            childCount == 0 ? nil : "children \(childCount)",
            scaleDescription,
            transform.offset == .zero ? nil : "position \(transform.offset.logDescription)",
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
            case let .texture(.file(name, _))?:
                fields.append("background \(name.nestedLogDescription)")
            case .texture, nil:
                break
            }
        case let .mesh(mesh):
            fields.append("polygons \(mesh.polygons.count)")
        default:
            break
        }

        let block: String
        switch fields.count {
        case 0:
            block = ""
        case 1:
            block = " { \(fields[0]) }"
        default:
            block = " {\n    \(fields.joined(separator: "\n    "))\n}"
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
        map { String(nestedLogDescriptionFor: $0) }.joined(separator: " ")
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
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
        let stepText = (step == 1) ? "" : " step \(step.logDescription)"
        return "\(start.logDescription) to \(end.logDescription)\(stepText)"
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}

extension Value: Loggable {
    public var loggableValue: Loggable {
        // Note: this switch is technically not needed, but serves to
        // ensure logging conformance is not forgotten for new types
        switch self {
        case let .color(color): return color
        case let .texture(texture): return texture
        case let .boolean(boolean): return boolean
        case let .number(number): return number
        case let .radians(radians): return radians
        case let .halfturns(halfturns): return halfturns
        case let .vector(vector): return vector
        case let .size(size): return size
        case let .rotation(rotation): return rotation
        case let .string(string): return string
        case let .text(text): return text
        case let .path(path): return path
        case let .mesh(mesh): return mesh
        case let .polygon(polygon): return polygon
        case let .point(point): return point
        case let .tuple(tuple): return tuple
        case let .range(range): return range
        case let .bounds(bounds): return bounds
        case let .object(object): return object
        }
    }

    public var logDescription: String {
        loggableValue.logDescription
    }

    public var nestedLogDescription: String {
        loggableValue.nestedLogDescription
    }
}
