//
//  Camera.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

extension Scene {
    func exportCamera(
        with options: ExportOptions,
        fallbackSize: (width: Int, height: Int),
        camera cameraOverride: Camera?
    ) throws -> ShapeScript.Camera {
        let selectedCamera = try cameraOverride ?? options.camera.map(camera(named:)) ?? cameras.first.map {
            Camera(geometry: $0, index: 0)
        } ?? .default
        let outputSize = options.outputSize(fallbackSize: fallbackSize, camera: selectedCamera)
        let width = outputSize.width
        let height = outputSize.height
        let aspectRatio = Double(height) / Double(width)
        let bounds = visibleBounds
        let size = bounds.size
        let center = bounds.center

        let distance: Double
        var scale: Double
        var offset = Vector(0, 0.000001, 0)
        switch selectedCamera.type {
        case .front, .back:
            distance = max(size.x * aspectRatio, size.y) + size.z / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .left, .right:
            distance = max(size.z * aspectRatio, size.y) + size.x / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .top, .bottom:
            distance = max(size.x * aspectRatio, size.z) + size.y / 2
            scale = max(size.x * aspectRatio, size.y * aspectRatio, size.z)
            offset = Vector(0, 0, 0.000001)
        default:
            distance = max(size.x * aspectRatio, size.y) + size.z / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        }
        scale /= 1.8

        var orientation = Rotation.identity
        var position = center - selectedCamera.direction * distance + offset
        if let geometry = selectedCamera.geometry {
            let transform = geometry.worldTransform
            orientation = transform.rotation
            if selectedCamera.hasPosition {
                position = transform.translation
            }
            if selectedCamera.hasScale {
                let v = transform.scale
                scale = max(v.x, v.y, v.z)
            }
        }

        if !selectedCamera.hasOrientation {
            orientation = Rotation(from: -.unitZ, to: center - position)
        }
        var camera = selectedCamera.settings
        camera.position = position
        camera.orientation = orientation
        camera.scale = Vector(scale, scale, scale)
        camera.fov = selectedCamera.fov
        camera.width = width
        camera.height = height
        camera.antialiased = options.antialiased
        return camera
    }

    func camera(named name: String) throws -> Camera {
        let cameras = CameraType.allCases.map {
            Camera(type: $0)
        } + self.cameras.enumerated().map { index, geometry in
            Camera(geometry: geometry, index: index)
        }
        let matches = cameras.filter {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            let cameraNames = cameras.map(\.name).joined(separator: ", ")
            throw NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Camera '\(name)' not found. Available cameras: \(cameraNames).",
            ])
        default:
            throw NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Camera name '\(name)' is ambiguous.",
            ])
        }
    }
}

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
