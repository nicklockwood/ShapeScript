//
//  ImportType.swift
//  ShapeScript
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

enum ImportType: Equatable, Sendable {
    case shape
    case text
    case json
    case image
    case font
    case csg
    case wavefront
    case stereolithography
    case object
    case model
    case unknown

    init(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "shape": self = .shape
        case "txt": self = .text
        case "json": self = .json
        case "csg": self = .csg
        case "obj": self = .wavefront
        case "stl", "stla": self = .stereolithography
        case "off": self = .object
        case "": self = .unknown
        case _ where url.isImageFile: self = .image
        case _ where url.isFontFile: self = .font
        default: self = .model
        }
    }
}
