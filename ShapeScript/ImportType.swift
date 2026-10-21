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
    case svg
    case wavefront
    case stereolithography
    case object
    case model
    case unknown

    init(_ url: URL, resolveFragment: Bool = true) {
        let url = resolveFragment ? URL(fileURLWithPath: ImportFileReference(url.path).path) : url
        switch url.pathExtension.lowercased() {
        case "shape": self = .shape
        case "txt": self = .text
        case "json": self = .json
        case "csg": self = .csg
        case "svg": self = .svg
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

struct ImportFileReference {
    let path: String
    let id: String?

    init(_ path: String) {
        if let hash = path.firstIndex(of: "#") {
            let file = String(path[..<hash])
            switch ImportType(URL(fileURLWithPath: file), resolveFragment: false) {
            case .shape, .svg, .csg, .wavefront, .stereolithography, .object, .model:
                self.path = file
                let fragment = String(path[path.index(after: hash)...])
                self.id = fragment.isEmpty ? nil : fragment.removingPercentEncoding ?? fragment
                return
            case .text, .json, .image, .font, .unknown:
                break
            }
        }
        self.path = path
        self.id = nil
    }
}
