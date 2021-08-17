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
    var logDescription: String { get }
}

extension Double: Loggable {
    public var logDescription: String {
        self < 0.0001 ? "0" : floor(self) == self ?
            "\(Int(self))" : String(format: "%.4g", self)
    }
}

extension Vector: Loggable {
    public var logDescription: String {
        "\(x.logDescription) \(y.logDescription) \(z.logDescription)"
    }
}

extension Angle: Loggable {
    public var logDescription: String {
        (radians / .pi).logDescription
    }
}

extension Rotation: Loggable {
    public var logDescription: String {
        "\(roll.logDescription) \(yaw.logDescription) \(pitch.logDescription)"
    }
}

extension Color: Loggable {
    public var logDescription: String {
        "\(r.logDescription) \(g.logDescription) \(b.logDescription) \(a.logDescription)"
    }
}

extension Texture: Loggable {
    public var logDescription: String {
        switch self {
        case let .file(name: _, url: url):
            return url.path
        case .data:
            return "texture { #data }"
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
}

extension Path: Loggable {
    public var logDescription: String {
        if subpaths.count > 1 {
            return "path { subpaths: \(subpaths.count) }"
        }
        return "path { points: \(points.count) }"
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
}
