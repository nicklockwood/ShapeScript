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

extension Double: Loggable {
    public var logDescription: String {
        self < 0.0001 ? "0" : floor(self) == self ?
            "\(Int(self))" : String(format: "%.4g", self)
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
        "\(r.logDescription) \(g.logDescription) \(b.logDescription) \(a.logDescription)"
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
            return "path { subpaths: \(subpaths.count) }"
        }
        return "path { points: \(points.count) }"
    }

    public var nestedLogDescription: String {
        "path"
    }
}

extension Geometry: Loggable {
    public var logDescription: String {
        let fields = [
            name.flatMap { $0.isEmpty ? nil : "    name: \($0)" },
            children.isEmpty ? nil : "    children: \(children.count)",
            "    size: \(transform.scale.logDescription)",
            "    position: \(transform.offset.logDescription)",
            "    orientation: \(transform.rotation.logDescription)",
        ].compactMap { $0 }.joined(separator: "\n")

        return """
        \(type) {
        \(fields)
        }
        """
    }

    public var nestedLogDescription: String {
        type.description
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
