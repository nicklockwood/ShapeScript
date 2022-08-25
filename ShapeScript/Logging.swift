//
//  Logging.swift
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

extension String: Loggable {
    public init(logDescriptionFor value: Any) {
        self.init(describing: (value as? Loggable)?.logDescription ?? value)
    }

    public init(nestedLogDescriptionFor value: Any) {
        self.init(describing: (value as? Loggable)?.nestedLogDescription ?? value)
    }

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
    public var logDescription: String {
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
        if r == b, b == g {
            components = [r]
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

private extension GeometryType {
    var logDescription: String {
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

        if case let .camera(camera) = type {
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
        type.logDescription
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

extension RangeValue: Loggable {
    public var logDescription: String {
        let stepText = (step == 1) ? "" : " step \(step.logDescription)"
        return "\(start.logDescription) to \(end.logDescription)\(stepText)"
    }

    public var nestedLogDescription: String {
        "(\(logDescription))"
    }
}
