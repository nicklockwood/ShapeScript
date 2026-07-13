//
//  Camera.swift
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
    static let front = Self(rawValue: "Front")
    static let back = Self(rawValue: "Back")
    static let left = Self(rawValue: "Left")
    static let right = Self(rawValue: "Right")
    static let top = Self(rawValue: "Top")
    static let bottom = Self(rawValue: "Bottom")

    static let allCases = [front, back, left, right, top, bottom]

    static func custom(_ index: Int) -> CameraType {
        Self(rawValue: index > 0 ? "Custom \(index + 1)" : "Custom")
    }
}

struct Camera {
    var type: CameraType
    var geometry: Geometry?
}

extension Camera: Equatable {
    static let `default` = Self(type: .front)

    init(type: CameraType) {
        self.type = type
    }

    init(geometry: Geometry, index: Int) {
        self.geometry = geometry
        self.type = .custom(index)
    }

    var name: String {
        geometry?.name ?? type.rawValue
    }

    var direction: Vector {
        Vector(0, 0, -1).rotated(by: orientation)
    }

    var orientation: Rotation {
        switch type {
        case .front: .identity
        case .back: .yaw(.pi)
        case .left: .yaw(.halfPi)
        case .right: .yaw(-.halfPi)
        case .top: .pitch(.halfPi)
        case .bottom: .pitch(-.halfPi)
        default: geometry?.transform.rotation ?? .identity
        }
    }

    var hasPosition: Bool {
        settings.position != nil
    }

    var hasOrientation: Bool {
        settings.orientation != nil
    }

    var hasScale: Bool {
        settings.scale != nil
    }

    var background: MaterialProperty? {
        settings.background
    }

    var fov: Angle {
        settings.fov ?? .degrees(60)
    }

    var isOrthographic: Bool? {
        settings.fov.map { $0 <= .zero }
    }

    var settings: ShapeScript.Camera {
        if case let .camera(settings) = geometry?.type {
            return settings
        }
        return .default
    }
}
