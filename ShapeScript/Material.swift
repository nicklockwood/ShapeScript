//
//  Material.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 16/01/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public typealias Color = Euclid.Color

public extension Color {
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

internal extension Color {
    init(unchecked components: [Double]) {
        if let color = Color(components) {
            self = color
        } else {
            assertionFailure()
            self = .clear
        }
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
