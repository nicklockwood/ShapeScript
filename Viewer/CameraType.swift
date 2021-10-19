//
//  CameraType.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

enum CameraType: String, Codable, CaseIterable {
    case front
    case back
    case left
    case right
    case top
    case bottom
}

extension CameraType {
    static let `default` = front

    var name: String {
        String(rawValue.first!).uppercased() + rawValue.dropFirst()
    }

    var direction: Vector {
        switch self {
        case .front: return Vector(0, 0, -1)
        case .back: return Vector(0, 0, 1)
        case .left: return Vector(1, 0, 0)
        case .right: return Vector(-1, 0, 0)
        case .top: return Vector(0, -1, 0)
        case .bottom: return Vector(0, 1, 0)
        }
    }

    var orientation: Rotation {
        switch self {
        case .front: return .identity
        case .back: return .yaw(.pi)
        case .left: return .yaw(.halfPi)
        case .right: return .yaw(-.halfPi)
        case .top: return .pitch(.halfPi)
        case .bottom: return .pitch(-.halfPi)
        }
    }
}
