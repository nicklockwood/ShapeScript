//
//  Material+Luminance.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 17/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

public extension MaterialProperty {
    var averageColor: Color {
        switch self {
        case let .color(color):
            color
        case let .texture(texture):
            texture.averageColor ?? .clear
        }
    }

    /// The average, aggregate luminance of the material when placed over a background color.
    func averageLuminance(over background: Color) -> Double {
        averageColor.luminance(over: background)
    }

    @available(*, deprecated, message: "Do not use")
    var brightness: Double {
        averageColor.brightness
    }

    @available(*, deprecated, renamed: "averageLuminance(over:)")
    func brightness(over background: Color) -> Double {
        averageColor.brightness(over: background)
    }
}

public extension Color {
    /// The aggregate luminance of a translucent color when placed over a background color.
    func luminance(over background: Color) -> Double {
        composited(over: background).luminance
    }

    @available(*, deprecated, message: "Do not use")
    func brightness(over background: Color) -> Double {
        brightness * alpha + background.brightness * (1 - alpha)
    }
}
