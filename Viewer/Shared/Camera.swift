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
        let bounds = geometry.withoutHiddenOrUnfocused().overestimatedBounds
        let selectedCamera = try cameraOverride ?? options.camera.map(camera(named:)) ?? cameras.first.map {
            Camera(geometry: $0, index: 0, zUp: zUp)
        } ?? Camera(bounds: bounds, zUp: zUp)
        let outputSize = options.outputSize(fallbackSize: fallbackSize, camera: selectedCamera)
        let width = outputSize.width
        let height = outputSize.height
        let aspectRatio = Double(height) / Double(width)
        let size = selectedCamera.framingSize(bounds.size)
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
        var position = center - selectedCamera.direction * distance +
            offset.rotated(by: selectedCamera.axisRotation)
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
            orientation = selectedCamera.geometry == nil ? selectedCamera.orientation :
                selectedCamera.lookOrientation(towards: center - position)
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
            Camera(type: $0, zUp: zUp)
        } + self.cameras.enumerated().map { index, geometry in
            Camera(geometry: geometry, index: index, zUp: zUp)
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
    var zUp: Bool
}

extension Camera: Equatable {
    static let `default` = Self(type: .front)

    init(bounds: Bounds, zUp: Bool) {
        let size = zUp ? Vector(bounds.size.x, bounds.size.z, bounds.size.y) : bounds.size
        // Prefer looking down on flat models, but not long, narrow or empty ones.
        let isFlat = !bounds.isEmpty && size.components.allSatisfy(\.isFinite) &&
            size.y < min(size.x, size.z) * 0.2
        self.init(type: isFlat ? .top : .front, zUp: zUp)
    }

    init(type: CameraType, zUp: Bool = false) {
        self.type = type
        self.zUp = zUp
    }

    init(geometry: Geometry, index: Int, zUp: Bool = false) {
        self.geometry = geometry
        self.type = .custom(index)
        self.zUp = zUp
    }

    var name: String {
        geometry?.name ?? type.rawValue
    }

    var direction: Vector {
        Vector(0, 0, -1).rotated(by: orientation)
    }

    var axisRotation: Rotation {
        zUp ? .pitch(-.halfPi) : .identity
    }

    var upVector: Vector {
        zUp ? .unitZ : .unitY
    }

    func framingSize(_ size: Vector) -> Vector {
        zUp ? Vector(size.x, size.z, size.y) : size
    }

    func lookOrientation(towards direction: Vector) -> Rotation {
        let alignment = Rotation(from: -.unitZ, to: direction)
        let up = upVector
        let forward = direction.normalized()
        let projectedUp = (up - forward * up.dot(forward)).normalized()
        guard projectedUp.lengthSquared > 0 else { return alignment }
        let currentUp = Vector.unitY.rotated(by: alignment)
        let angle = atan2(forward.dot(currentUp.cross(projectedUp)), currentUp.dot(projectedUp))
        return (Rotation(axis: forward, angle: .radians(-angle)) ?? .identity) * alignment
    }

    var orientation: Rotation {
        let orientation: Rotation = switch type {
        case .front: .identity
        case .back: .yaw(.pi)
        case .left: .yaw(.halfPi)
        case .right: .yaw(-.halfPi)
        case .top: .pitch(.halfPi)
        case .bottom: .pitch(-.halfPi)
        default: geometry?.transform.rotation ?? .identity
        }
        return geometry == nil ? axisRotation * orientation : orientation
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
