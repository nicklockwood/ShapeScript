//
//  ViewTests.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 10/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import SceneKit
import XCTest

private typealias ViewMockDocument = MockDocument<MockViewController>

private final class MockViewController: DocumentViewControllerProtocol, @unchecked Sendable {
    static let documentBackgroundColor = Color.clear

    weak var document: ViewMockDocument?
    let scnScene = SCNScene()
    var renderTimer: Timer?
    let scnView: SCNView = PivotResettingSCNView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let errorTextView = OSTextView()
    let grantAccessButton = OSButton()
    var isQuickLook = false
    lazy var cameraNode = makeCameraNode()
    var axesNode: SCNNode?
    var errorMessage: NSAttributedString?
    var isLoading = false
    var renderProgress: Double?
    var consoleVisibilityChanges = [Bool]()
    var showConsole = false {
        didSet {
            if showConsole != oldValue {
                consoleVisibilityChanges.append(showConsole)
            }
        }
    }

    var showAxes = false
    var isOrthographic = false
    var camera = Viewer.Camera.default
    var background: MaterialProperty?
    var selectedGeometry: Geometry?
    var warningPresentation: WarningQueue.Presentation?
    var sceneRefreshCount = 0
    var refreshEvents = [String]()
    var orthographicWhenRefreshed: Bool?
    var cameraHadMovedAfterReset: Bool?

    func didRefreshScene() {
        sceneRefreshCount += 1
        refreshEvents.append("scene")
    }

    func didRefreshCamera() {
        refreshEvents.append("camera")
    }

    func didRefreshOrthographic() {
        orthographicWhenRefreshed = scnView.pointOfView?.camera?.usesOrthographicProjection
        refreshEvents.append("orthographic")
    }

    func didResetView() {
        cameraHadMovedAfterReset = cameraHasMoved
        refreshEvents.append("reset")
    }

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
    var consoleWasVisibleWhenCleared: Bool?
    func clearLog() {
        consoleWasVisibleWhenCleared = showConsole
        hasLog = false
    }

    func appendLog(_ text: String) { hasLog = hasLog || !text.isEmpty }
    func updateModals() {}
    func copyCamera() {}
}

private final class PivotResettingSCNView: SCNView {
    override var pointOfView: SCNNode? {
        get { super.pointOfView }
        set {
            super.pointOfView = newValue
            defaultCameraController.target = .init(0, 0, 0)
        }
    }
}

@MainActor
final class ViewTests: XCTestCase {
    func testRefreshHooksRunAfterSharedRenderingWork() {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.scene = .empty
        viewController.scnView.pointOfView = SCNNode()
        viewController.scnView.pointOfView?.camera = SCNCamera()

        viewController.refreshCamera()
        XCTAssertEqual(viewController.refreshEvents, ["camera"])

        viewController.isOrthographic = true
        viewController.refreshOrthographic()
        XCTAssertEqual(viewController.refreshEvents, ["camera", "orthographic"])
        XCTAssertEqual(viewController.orthographicWhenRefreshed, true)
        XCTAssertEqual(viewController.cameraNode.camera?.usesOrthographicProjection, true)

        viewController.refreshEvents = []
        viewController.resetCamera()
        XCTAssertEqual(viewController.refreshEvents, ["camera", "reset"])
        XCTAssertEqual(viewController.cameraHadMovedAfterReset, false)
        XCTAssertTrue(viewController.scnView.pointOfView === viewController.cameraNode)
    }

    func testCameraControllerOrbitsAroundDocumentUpAxisAfterReset() throws {
        let viewController = MockViewController()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csg")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = ViewMockDocument(fileURL: url, viewController: viewController)
        viewController.document = document
        viewController.scnView.scene = viewController.scnScene
        viewController.scnScene.rootNode.addChildNode(viewController.cameraNode)
        document.scene = try Scene(csgString: "cube(2,true);", isCancelled: { false })
        let controller = viewController.scnView.defaultCameraController
        for zUp in [true, false, true] {
            document.documentFileURL = url.deletingPathExtension().appendingPathExtension(zUp ? "csg" : "shape")
            document.scene = document.scene?.with(zUp: zUp)
            document.updateViews()
            viewController.resetView()
            let up = zUp ? SCNVector3(0, 0, 1) : SCNVector3(0, 1, 0)
            XCTAssertEqualVector(controller.worldUp, up)
            controller.rotateBy(x: 45, y: 0)
            let cameraNode = try XCTUnwrap(controller.pointOfView)
            XCTAssertEqual(zUp ? cameraNode.position.z : cameraNode.position.y, 0, accuracy: 0.001)
            XCTAssertGreaterThan(abs(cameraNode.position.x), 0.1)
            XCTAssertEqualVector(cameraNode.worldUp, up)
        }
    }

    func testRefreshSceneUpdatesViewPivotCenterAfterBoundsChange() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        viewController.scnView.pointOfView = viewController.cameraNode

        try updateView(viewController, document, source: "cube { position 10 }")
        XCTAssertEqualVector(viewController.scnView.defaultCameraController.target, SCNVector3(10, 0, 0))

        try updateView(viewController, document, source: "cube { position -20 4 6 }")
        XCTAssertEqualVector(viewController.scnView.defaultCameraController.target, SCNVector3(-20, 4, 6))
    }

    func testDocumentUpdatesRefreshSceneAndClearRemovedGeometry() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        viewController.scnView.pointOfView = viewController.cameraNode
        try updateView(viewController, document, source: "cube")
        XCTAssertEqual(viewController.sceneRefreshCount, 1)
        let scene = try XCTUnwrap(document.scene)
        let cube = try XCTUnwrap(scene.children.first)
        let node = try XCTUnwrap(cube.scnNode)
        XCTAssertTrue(viewController.geometry === scene.geometry)
        XCTAssertTrue(node.parent === viewController.scnScene.rootNode)
        XCTAssertTrue(cube.parent === scene.geometry)
        viewController.selectGeometry(node)
        XCTAssertTrue(viewController.selectedGeometry === cube)

        document.updateViews()
        XCTAssertEqual(viewController.sceneRefreshCount, 2)
        XCTAssertTrue(viewController.geometry === scene.geometry)
        XCTAssertTrue(cube.scnNode === node)
        XCTAssertTrue(viewController.selectedGeometry === cube)
        XCTAssertTrue(cube.parent === scene.geometry)

        document.scene = nil
        document.updateViews()
        XCTAssertEqual(viewController.sceneRefreshCount, 3)
        XCTAssertNil(viewController.geometry)
        XCTAssertNil(viewController.selectedGeometry)
        XCTAssertTrue(viewController.scnScene.rootNode.childNodes.isEmpty)
    }

    func testReloadRetainsConsoleUntilNewOutputIsKnown() async throws {
        for (source, hasOutput) in [
            ("print \"hello\"\ncube", true),
            ("cube", false),
            ("print \"\"\ncube", false),
        ] {
            let viewController = MockViewController()
            let document = ViewMockDocument(viewController: viewController)
            viewController.document = document
            viewController.showConsole = true
            viewController.appendLog("Previous output")
            viewController.consoleVisibilityChanges = []
            document.sourceString = source
            document.didUpdateSource()

            // Complete on the main queue after the queued log and status updates.
            let progress = try XCTUnwrap(document.loadingProgress)
            let completed = expectation(description: "Reload finishes")
            progress.dispatch { _ in
                DispatchQueue.main.async {
                    completed.fulfill()
                }
            }
            await fulfillment(of: [completed], timeout: 5)

            XCTAssertTrue(progress.didSucceed, source)
            XCTAssertEqual(viewController.consoleWasVisibleWhenCleared, true, source)
            XCTAssertEqual(viewController.hasLog, hasOutput, source)
            XCTAssertEqual(viewController.showConsole, hasOutput, source)
            XCTAssertEqual(viewController.consoleVisibilityChanges, hasOutput ? [] : [false], source)
        }
    }

    func testSourceUpdatePreservesOriginalErrorUntilSuccess() async throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "cube {"
        do {
            _ = try parse("cube {")
            XCTFail("Expected a missing-brace error")
            return
        } catch {
            document.error = ProgramError(error)
        }
        document.updateViews()
        let originalMessage = try XCTUnwrap(viewController.errorMessage)

        document.sourceString = "cube {}"
        document.didUpdateSource()
        document.updateViews()
        XCTAssertNotNil(document.error)
        XCTAssertEqual(viewController.errorMessage, originalMessage)
        XCTAssertEqual(document.errorMessage, originalMessage)

        let progress = try XCTUnwrap(document.loadingProgress)
        let completed = expectation(description: "Corrected source finishes rendering")
        progress.dispatch { _ in completed.fulfill() }
        await fulfillment(of: [completed], timeout: 5)
        document.updateViews()
        XCTAssertTrue(progress.didSucceed)
        XCTAssertNil(document.error)
        XCTAssertNil(viewController.errorMessage)
        XCTAssertNotNil(document.scene)
    }

    func testSourceUpdatePreservesErrorDuringProgressAndReplacesItOnFailure() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "cube {"
        let originalError = ProgramError(CSGImportError(message: "Original error", line: 1, column: 1))
        document.error = originalError
        document.updateViews()
        let originalMessage = try XCTUnwrap(viewController.errorMessage)

        document.sourceString = "sphere {"
        document.didUpdateSource()
        let progress = try XCTUnwrap(document.loadingProgress)
        progress.setStatus(.partial(.empty, 0.1))
        document.updateViews()
        XCTAssertEqual(document.error, originalError)
        XCTAssertEqual(viewController.errorMessage, originalMessage)

        let replacementError = ProgramError(CSGImportError(message: "Replacement error", line: 1, column: 1))
        progress.setStatus(.failure(replacementError))
        XCTAssertEqual(document.error, replacementError)
        XCTAssertEqual(viewController.errorMessage, replacementError.message(with: document.sourceString))
        XCTAssertNotEqual(viewController.errorMessage, originalMessage)
    }

    func testOutdatedSourceErrorDoesNotReplaceDisplayedError() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "cube {"
        let originalError = ProgramError(CSGImportError(message: "Original error", line: 1, column: 1))
        document.error = originalError
        document.updateViews()
        let originalMessage = try XCTUnwrap(viewController.errorMessage)
        document.didUpdateSource()
        let progress = try XCTUnwrap(document.loadingProgress)

        document.sourceString = "cube {}"
        let outdatedError = ProgramError(CSGImportError(message: "Outdated error", line: 1, column: 1))
        progress.setStatus(.failure(outdatedError))
        document.updateViews()
        XCTAssertEqual(document.error, originalError)
        XCTAssertEqual(viewController.errorMessage, originalMessage)
    }

    func testLoadingProgressFinalUpdateWaitsForScheduledUpdate() async {
        let progress = LoadingProgress { _ in }
        let previewStarted = DispatchSemaphore(value: 0)
        let releasePreview = DispatchSemaphore(value: 0)
        let previewFinished = DispatchSemaphore(value: 0)
        let finalStarted = DispatchSemaphore(value: 0)
        let finalFinished = DispatchSemaphore(value: 0)
        let completed = expectation(description: "Final update completes")

        progress.schedule(after: 0) {
            previewStarted.signal()
            XCTAssertEqual(releasePreview.wait(timeout: .now() + 5), .success)
            previewFinished.signal()
        }
        XCTAssertEqual(previewStarted.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            finalStarted.signal()
            progress.performUpdate {
                XCTAssertEqual(previewFinished.wait(timeout: .now()), .success)
            }
            finalFinished.signal()
            completed.fulfill()
        }
        XCTAssertEqual(finalStarted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(finalFinished.wait(timeout: .now() + 0.05), .timedOut)
        releasePreview.signal()
        await fulfillment(of: [completed], timeout: 5)
    }

    private func updateView(_: MockViewController, _ document: ViewMockDocument, source: String) throws {
        document.scene = try evaluate(parse(source), delegate: nil)
        document.updateViews()
    }

    private func XCTAssertEqualVector(
        _ actual: SCNVector3,
        _ expected: SCNVector3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.001, file: file, line: line)
    }
}
