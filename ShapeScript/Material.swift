//
//  Material.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 16/01/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import Foundation

public struct Color: Hashable {
    public let r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public extension Color {
    static let clear = Color(0, 0)
    static let white = Color(1)
    static let black = Color(0)

    init(_ rgb: Double, _ a: Double = 1) {
        r = rgb
        g = rgb
        b = rgb
        self.a = a
    }

    var components: [Double] { [r, g, b, a] }

    init(unchecked components: [Double]) {
        var a = 1.0
        switch components.count {
        case 4:
            a = components[3]
            fallthrough
        case 3:
            r = components[0]
            g = components[1]
            b = components[2]
        case 2:
            a = components[1]
            fallthrough
        case 1:
            r = components[0]
            g = r
            b = r
        default:
            preconditionFailure()
        }
        self.a = a
    }

    init?(hexString: String) {
        var string = hexString
        if hexString.hasPrefix("#") {
            string = String(string.dropFirst())
        }
        switch string.count {
        case 3:
            string += "f"
            fallthrough
        case 4:
            let chars = Array(string)
            let red = chars[0]
            let green = chars[1]
            let blue = chars[2]
            let alpha = chars[3]
            string = "\(red)\(red)\(green)\(green)\(blue)\(blue)\(alpha)\(alpha)"
        case 6:
            string += "ff"
        case 8:
            break
        default:
            return nil
        }
        guard let rgba = Double("0x" + string).flatMap({
            UInt32(exactly: $0)
        }) else {
            return nil
        }
        let red = Double((rgba & 0xFF00_0000) >> 24) / 255
        let green = Double((rgba & 0x00FF_0000) >> 16) / 255
        let blue = Double((rgba & 0x0000_FF00) >> 8) / 255
        let alpha = Double((rgba & 0x0000_00FF) >> 0) / 255
        self.init(unchecked: [red, green, blue, alpha])
    }
}

public enum Texture: Hashable {
    case file(name: String, url: URL)
    case data(Data)
}

public enum MaterialProperty: Hashable {
    case color(Color)
    case texture(Texture)

    init?(_ value: Any) {
        switch value {
        case let color as Color:
            self = .color(color)
        case let texture as Texture:
            self = .texture(texture)
        default:
            return nil
        }
    }
}

public struct Material: Hashable {
    public var opacity = 1.0
    public var texture: Texture?
    public var color: Color? = .white {
        // Color and texture are mutually exclusive
        didSet { texture = (color != nil) ? nil : texture }
    }

    public var isOpaque: Bool {
        opacity > 0.999 && (color?.a ?? 1) > 0.999
    }

    public static let `default` = Material()

    public init() {}
}
