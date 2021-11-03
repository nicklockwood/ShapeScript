//
//  CameraType.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import ShapeScript

struct CameraType: RawRepresentable, Hashable, Codable {
    let rawValue: String
}

extension CameraType: CaseIterable {
    static let front = Self(rawValue: "front")
    static let back = Self(rawValue: "back")
    static let left = Self(rawValue: "left")
    static let right = Self(rawValue: "right")
    static let top = Self(rawValue: "top")
    static let bottom = Self(rawValue: "bottom")

    static var allCases = [front, back, left, right, top, bottom]
}

struct Camera: Hashable {
    var type: CameraType
    var geometry: Geometry?
}

extension Camera {
    static let `default` = Self(type: .front)

    init(type: CameraType) {
        self.type = type
    }

    init(geometry: Geometry, name: String) {
        self.geometry = geometry
        type = CameraType(rawValue: name)
    }

    var name: String {
        String(type.rawValue.first!).uppercased() + type.rawValue.dropFirst()
    }

    var direction: Vector {
        Vector(0, 0, -1).rotated(by: orientation)
    }

    var orientation: Rotation {
        switch type {
        case .front: return .identity
        case .back: return .yaw(.pi)
        case .left: return .yaw(.halfPi)
        case .right: return .yaw(-.halfPi)
        case .top: return .pitch(.halfPi)
        case .bottom: return .pitch(-.halfPi)
        default:
            return geometry?.transform.rotation ?? .identity
        }
    }

    var hasPosition: Bool {
        settings?.hasPosition ?? false
    }

    var hasOrientation: Bool {
        settings?.hasOrientation ?? false
    }

    var hasScale: Bool {
        settings?.hasScale ?? false
    }

    var fov: Angle? {
        settings?.fov
    }

    var isOrthographic: Bool? {
        fov.map { $0 <= .zero }
    }

    private var settings: ShapeScript.Camera? {
        if case let .camera(settings) = geometry?.type {
            return settings
        }
        return nil
    }
}
