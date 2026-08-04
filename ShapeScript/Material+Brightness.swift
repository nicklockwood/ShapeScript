//
//  Material+Brightness.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 17/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

public extension MaterialProperty {
    var brightness: Double {
        averageColor.brightness
    }

    func brightness(over background: Color) -> Double {
        averageColor.brightness(over: background)
    }

    var averageColor: Color {
        switch self {
        case let .color(color):
            color
        case let .texture(texture):
            texture.averageColor ?? .clear
        }
    }
}

public extension Color {
    func brightness(over background: Color) -> Double {
        brightness * alpha + background.brightness * (1 - alpha)
    }
}
