//
//  ModelInfoTests.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 08/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import SceneKit
import XCTest

private typealias ModelInfoMockDocument = MockDocument<ModelInfoMockViewController>

private final class ModelInfoMockViewController: DocumentViewControllerProtocol, @unchecked Sendable {
    static let documentBackgroundColor = Color.clear

    weak var document: ModelInfoMockDocument?
    let scnScene = SCNScene()
    var renderTimer: Timer?
    let scnView = SCNView()
    let errorTextView = OSTextView()
    let grantAccessButton = OSButton()
    var isQuickLook = false
    let cameraNode = SCNNode()
    var axesNode: SCNNode?
    var errorMessage: NSAttributedString?
    var isLoading = false
    var renderProgress: Double?
    var showConsole = false
    var showAxes = false
    var isOrthographic = false
    var camera = Viewer.Camera.default
    var background: MaterialProperty?
    var selectedGeometry: Geometry?
    var warningPresentation: WarningQueue.Presentation?

    func presentError(_: Error, completionHandler: (() -> Void)?) -> Bool {
        completionHandler?()
        return true
    }

    func showWarning(
        _: NSAttributedString,
        onNext _: @escaping @MainActor @Sendable () -> Void,
        onDismissAll: @escaping @MainActor @Sendable () -> Void
    ) {
        onDismissAll()
    }

    func hideWarning() {}

    var hasLog = false
    func clearLog() { hasLog = false }
    func appendLog(_ text: String) { hasLog = hasLog || !text.isEmpty }
    func updateModals() {}
    func copyCamera() {}
}

@MainActor
final class ModelInfoTests: XCTestCase {
    func testModelInfoForEmptyCodeOnlyScene() {
        let document = ModelInfoMockDocument()
        document.sourceString = """
        define size 10
        let color = red
        """
        document.scene = .empty
        let progress = LoadingProgress { _ in }
        progress.setStatus(.success(.empty))
        document.loadingProgress = progress

        XCTAssertEqual(document.modelInfo, """
        No visible geometry

        """)
    }

    func testModelInfoForEmptySceneWhileLoading() {
        let document = ModelInfoMockDocument()
        document.sourceString = "define size 10"
        document.scene = .empty
        let progress = LoadingProgress { _ in }
        progress.setStatus(.partial(.empty, 0))
        document.loadingProgress = progress

        XCTAssertEqual(document.modelInfo, """
        No visible geometry

        """)
    }

    func testModelInfoCalculatesSelectedLoadedGeometryWhileSceneIsLoading() throws {
        let viewController = ModelInfoMockViewController()
        let document = ModelInfoMockDocument(viewController: viewController)
        viewController.document = document
        let scene = try evaluate(parse("""
        cube
        sphere
        """), delegate: nil)
        let cube = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(cube.build { false })
        viewController.selectedGeometry = cube
        document.scene = scene
        let progress = LoadingProgress { _ in }
        progress.setStatus(.partial(scene, 0))
        document.loadingProgress = progress

        XCTAssert(cube.hasBuiltMeshes)
        let modelInfo = document.modelInfo
        XCTAssert(modelInfo.contains("Type: cube"), modelInfo)
        XCTAssert(modelInfo.contains("Triangles: 12"), modelInfo)
        XCTAssertFalse(modelInfo.contains("calculating…"), modelInfo)
    }

    func testModelInfoKeepsCalculatingForSelectedUnloadedGeometryWhileSceneIsLoading() throws {
        let viewController = ModelInfoMockViewController()
        let document = ModelInfoMockDocument(viewController: viewController)
        viewController.document = document
        let scene = try evaluate(parse("""
        cube
        sphere
        """), delegate: nil)
        let sphere = try XCTUnwrap(scene.children.last)
        viewController.selectedGeometry = sphere
        document.scene = scene
        let progress = LoadingProgress { _ in }
        progress.setStatus(.partial(scene, 0))
        document.loadingProgress = progress

        XCTAssertFalse(sphere.hasBuiltMeshes)
        let modelInfo = document.modelInfo
        XCTAssert(modelInfo.contains("Type: sphere"), modelInfo)
        XCTAssert(modelInfo.contains("Triangles: calculating…"), modelInfo)
    }
}
