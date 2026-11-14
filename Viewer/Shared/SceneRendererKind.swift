//
//  SceneRendererKind.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 06/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

enum SceneRendererKind: String, CaseIterable, Codable, Sendable {
    case sceneKit
    case realityKit

    var isSupported: Bool {
        switch self {
        case .sceneKit:
            true
        case .realityKit:
            Self.isRealityKitSupported
        }
    }

    private static var isRealityKitSupported: Bool {
        if #available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *) {
            return true
        }
        return false
    }

    var displayName: String {
        switch self {
        case .sceneKit:
            "SceneKit"
        case .realityKit:
            "RealityKit"
        }
    }
}
