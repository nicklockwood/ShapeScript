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
    var width: Int?
    var height: Int?
}

extension ShapeScriptCommand {
    static var exportValueOptions: [String] {
        ["--output", "-o", "--width", "--height"]
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export a ShapeScript document."
        )

        @Argument(help: "Input .shape file.")
        var inputPath: String

        @Flag(help: "Evaluate the document in preview mode.")
        var preview = false

        @OptionGroup
        var cacheOptions: CacheOptions

        @Option(name: .shortAndLong, help: "Exported model file.")
        var output: String?

        @Option(help: "Width in pixels for image exports.")
        var width: Int?

        @Option(help: "Height in pixels for image exports.")
        var height: Int?

        @Flag(help: "Output model using Z as up axis instead of Y.")
        var zUp = false

        @Argument(parsing: .postTerminator, help: "Top-level script options as --name value pairs.")
        var scriptOptions: [String] = []

        init() {}

        mutating func validate() throws {
            if let width, width <= 0 {
                throw ValidationError("--width option expects a positive integer")
            }
            if let height, height <= 0 {
                throw ValidationError("--height option expects a positive integer")
            }
        }

        mutating func run() throws {
            let directory = FileManager.default.currentDirectoryPath
            let exportOptions = ExportOptions(convertToZUp: zUp, width: width, height: height)
            let runner = try CLIRunner(
                directory: directory,
                inputPath: inputPath,
                preview: preview,
                scriptOptions: scriptOptions,
                cacheOptions: cacheOptions
            )
            let outputURL = try output.map {
                try CLIRunner.exportURL(for: $0, in: directory)
            } ?? runner.defaultExportURL(with: exportOptions)
            try runner.export(to: outputURL, options: exportOptions)
        }
    }
}

extension CLIRunner {
    static let exportTypes = ["stl", "stla", "bmp"]

    static func exportURL(for outputPath: String, in directory: String) throws -> URL {
        let url = expandPath(outputPath, in: directory)
        guard exportTypes.contains(url.pathExtension.lowercased()) else {
            throw CLIError("Unsupported export file type '\(url.pathExtension)'")
        }
        return url
    }

    func export(to url: URL, options: ExportOptions) throws {
        let scene = try loadScene()
        printStatus("Exporting to '\(url.lastPathComponent)' ...")
        let geometry = scene.geometry
        if url.pathExtension.lowercased() == "bmp" {
            try exportBMP(scene, geometry: geometry, to: url, with: options)
            printStatus("Export complete")
            return
        }
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
        printStatus("Export complete")
    }
}
