//
//  CLI+Export.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 07/05/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import ArgumentParser
import Euclid
import Foundation
import ShapeScript

struct ExportOptions {
    var convertToZUp: Bool
}

extension ShapeScriptCommand {
    static var exportValueOptions: [String] {
        ["--output", "-o"]
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export a ShapeScript document."
        )

        @Argument(help: "Input .shape file.")
        var inputPath: String

        @Option(name: .shortAndLong, help: "Exported model file.")
        var output: String?

        @Flag(help: "Output model using Z as up axis instead of Y.")
        var zUp = false

        init() {}

        mutating func run() throws {
            let directory = FileManager.default.currentDirectoryPath
            let exportOptions = ExportOptions(convertToZUp: zUp)
            let runner = try CLIRunner(
                directory: directory,
                inputPath: inputPath
            )
            let outputURL = try output.map {
                try CLIRunner.exportURL(for: $0, in: directory)
            } ?? runner.defaultExportURL
            try runner.export(to: outputURL, options: exportOptions)
        }
    }
}

extension CLIRunner {
    static let exportTypes = ["stl", "stla"]

    static func exportURL(for outputPath: String, in directory: String) throws -> URL {
        let url = expandPath(outputPath, in: directory)
        guard exportTypes.contains(url.pathExtension) else {
            throw CLIError("Unsupported export file type '\(url.pathExtension)'")
        }
        return url
    }

    func export(to url: URL, options: ExportOptions) throws {
        let scene = try loadScene()
        print("Exporting to '\(url.lastPathComponent)' ...")
        let geometry = scene.geometry
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
        print("Export complete")
    }
}
