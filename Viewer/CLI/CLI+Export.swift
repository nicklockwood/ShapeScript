//
//  CLI+Export.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 07/05/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

struct ExportOptions {
    var convertToZUp: Bool
}

extension ExportOptions {
    static let arguments: [(name: String, help: String)] = [
        ("z-up", "Output model using Z as up axis instead of Y"),
    ]

    init(arguments: [String: String]) throws {
        self.convertToZUp = try arguments["z-up"].map {
            guard $0 == "" else {
                throw CLIError("--z-up option does not expect a value")
            }
            return true
        } ?? false
    }
}

extension CLI {
    static let exportTypes: [String] = ["stl", "stla"]

    func export(_ geometry: Geometry, to url: URL, with options: ExportOptions) throws {
        var mesh = geometry.merged()
        if options.convertToZUp {
            mesh.rotate(by: .pitch(.degrees(-90)))
        }
        switch url.pathExtension.lowercased() {
        case "stl":
            let stl = mesh.stlData(colorLookup: { ($0 as? Material)?.color })
            try stl.write(to: url, options: .atomic)
        case "stla":
            let name = geometry.name ?? url.deletingPathExtension().lastPathComponent
            let stl = mesh.stlString(name: name)
            try stl.write(to: url, atomically: true, encoding: .utf8)
        case let ext:
            throw CLIError("Unsupported export file type '\(ext)'")
        }
    }
}
