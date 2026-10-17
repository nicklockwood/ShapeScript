//
//  TestUtils.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 03/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import SceneKit
import XCTest

let testsDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent()

final class TestDelegate: EvaluationDelegate {
    let directory: URL
    init(directory: URL = testsDirectory) {
        self.directory = directory
    }

    var imports = [String]()
    func resolveURL(for name: String) -> URL {
        imports.append(name)
        return directory.appendingPathComponent(name)
    }

    var log = [AnyHashable?]()
    func debugLog(_ values: [AnyHashable]) {
        log += values
    }
}

final class MockDocument<ViewController: DocumentViewControllerProtocol>: DocumentProtocol, @unchecked Sendable {
    static var backgroundColor: OSColor { .clear }

    let cache = GeometryCache(diskCache: nil)
    var refreshCacheOnReload = false
    let settings = Settings.shared
    var documentFileURL: URL?
    var fileMonitor: FileMonitor?
    let viewController: ViewController?

    var scene: Scene?
    var loadingProgress: LoadingProgress?
    var exportProgress: LoadingProgress?
    var sourceString = ""
    var errorMessage: NSAttributedString?
    var error: ProgramError? {
        didSet { errorMessage = error?.message(with: sourceString) }
    }

    @MainActor let warningQueue = WarningQueue()
    var cameras = [Viewer.Camera]()

    init(
        fileURL: URL? = nil,
        fileMonitor: FileMonitor? = nil,
        viewController: ViewController? = nil
    ) {
        self.documentFileURL = fileURL
        self.fileMonitor = fileMonitor
        self.viewController = viewController
    }

    func resolveURL(for path: String) -> URL {
        URL(fileURLWithPath: path)
    }
}

func evaluate(
    _ program: Program,
    options: [String: Any] = [:],
    delegate: EvaluationDelegate?,
    isCancelled: @escaping CancellationHandler = { false }
) throws -> Scene {
    try ShapeScript.evaluate(
        program,
        options: options,
        delegate: delegate,
        cache: GeometryCache(diskCache: nil),
        isCancelled: isCancelled
    )
}

func evaluate(_ shapeURL: URL) throws -> Geometry {
    let input = try String(contentsOf: shapeURL, encoding: .utf8)
    return try evaluate(input, directory: shapeURL.deletingLastPathComponent())
}

func evaluate(_ input: String, directory: URL = testsDirectory) throws -> Geometry {
    let program = try parse(input)
    let delegate = TestDelegate(directory: directory)
    let scene = try evaluate(program, delegate: delegate)
    return Geometry(
        type: .group,
        name: nil,
        transform: .identity,
        material: .default,
        smoothing: nil,
        children: scene.children,
        sourceLocation: nil
    )
}
