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
    var onRenderComplete: (() -> Void)?
    var renderProgress: Double? {
        didSet {
            if renderProgress == 1 {
                onRenderComplete?()
            }
        }
    }

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
    func testExportCameraIgnoresCSGBackgroundGeometry() throws {
        let options = ExportOptions(convertToZUp: false, camera: nil, width: nil, height: nil)
        let model = try Scene(csgString: "cube(2,true);", isCancelled: { false })
        let preview = try Scene(
            csgString: "cube(2,true); %translate([20,0,0]) cube(10,true);",
            isCancelled: { false }
        )
        XCTAssertNotEqual(model.visibleBounds, preview.visibleBounds)
        let expected = try model.exportCamera(with: options, fallbackSize: (320, 320), camera: nil)
        let actual = try preview.exportCamera(with: options, fallbackSize: (320, 320), camera: nil)
        XCTAssertEqual(actual, expected)
    }

    @available(macOS 13.0, *)
    func testRerenderAfterFailurePreservesErrorWithoutEvaluatingSource() async throws {
        let partialScene = try evaluate(parse("cube"), delegate: nil)
        XCTAssertTrue(partialScene.build { false })
        for scene in [Scene.empty, partialScene] {
            let viewController = MockViewController()
            let document = ViewMockDocument(viewController: viewController)
            viewController.document = document
            document.sourceString = "print \"Should not run\"\nsphere"
            document.scene = scene
            let error = ProgramError(CSGImportError(message: "Original error", line: 1, column: 1))
            document.error = error
            let progress = LoadingProgress { _ in }
            progress.setStatus(.failure(error))
            document.loadingProgress = progress
            document.updateViews()

            // Appearance changes and display settings both use this path.
            document.rerender()
            for _ in 0 ..< 200 {
                if document.loadingProgress?.inProgress == false { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            document.updateViews()
            XCTAssertTrue(document.loadingProgress?.isCancelledOrFailed == true)
            XCTAssertEqual(document.error, error)
            XCTAssertTrue(document.scene === scene)
            XCTAssertFalse(viewController.hasLog)
            XCTAssertNil(viewController.consoleWasVisibleWhenCleared)
            XCTAssertFalse(viewController.isLoading)
            XCTAssertNil(viewController.renderProgress)
        }
    }

    @available(macOS 13.0, *)
    func testLoadingIndicatorTransitionsBetweenSpinnerAndProgress() async throws {
        let indicator = ProgressView(frame: .zero)
        let spinner = try XCTUnwrap(indicator.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let ring = try XCTUnwrap(indicator.subviews.compactMap { $0 as? CircularProgressView }.first)
        defer { indicator.isActive = false }
        indicator.isActive = true
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(spinner.controlSize, .small)
        XCTAssertEqual(spinner.alphaValue, 1)
        XCTAssertEqual(ring.alphaValue, 0)

        // Progress updates must not shorten or restart the initial spinner interval.
        indicator.progress = 0.2
        try await Task.sleep(for: .milliseconds(2000))
        XCTAssertEqual(spinner.alphaValue, 0)
        XCTAssertEqual(ring.alphaValue, 1)

        try await Task.sleep(for: .seconds(4))
        XCTAssertEqual(spinner.alphaValue, 0)
        XCTAssertEqual(ring.alphaValue, 1)

        try await Task.sleep(for: .seconds(5))
        XCTAssertEqual(spinner.alphaValue, 1)
        XCTAssertEqual(ring.alphaValue, 0)

        indicator.progress = 0.4
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(spinner.alphaValue, 0)
        XCTAssertEqual(ring.alphaValue, 1)
        indicator.isActive = false
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(indicator.isHidden)
    }

    @available(macOS 13.0, *)
    func testShortLoadingIndicatorFadesOutAndRestartsWithSpinner() async throws {
        let indicator = ProgressView(frame: .zero)
        let spinner = try XCTUnwrap(indicator.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let ring = try XCTUnwrap(indicator.subviews.compactMap { $0 as? CircularProgressView }.first)
        defer { indicator.isActive = false }
        indicator.isActive = true
        try await Task.sleep(for: .milliseconds(600))
        indicator.isActive = false
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(indicator.isHidden)
        XCTAssertEqual(ring.alphaValue, 0)

        indicator.isActive = true
        try await Task.sleep(for: .milliseconds(1200))
        // The previous load's timer must not switch this load to progress early.
        XCTAssertFalse(indicator.isHidden)
        XCTAssertEqual(spinner.alphaValue, 1)
        XCTAssertEqual(ring.alphaValue, 0)
    }

    @available(macOS 13.0, *)
    func testLoadingFailureHidesProgressIndicator() async throws {
        let document = Document()
        let controller = DocumentViewController()
        document.addWindowController(NSWindowController(window: NSWindow(contentViewController: controller)))
        defer { document.close() }
        XCTAssertTrue(document.viewController === controller)
        let indicator = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ProgressView }.first)
        for source in ["cube {", "cube\nunknownSymbol", "import \"missing.shape\""] {
            document.error = nil
            document.sourceString = source
            for _ in 0 ..< 200 {
                if document.error != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotNil(document.error)
            XCTAssertFalse(controller.isLoading)
            XCTAssertNil(controller.renderProgress)
            XCTAssertFalse(indicator.isActive)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertTrue(indicator.isHidden)
        }
    }

    func testBackgroundColorRemainsResolvedAcrossAppearanceChanges() throws {
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        NSApp.appearance = lightAppearance
        let light = Document.backgroundColor
        let lightComponents = Color(light)
        NSApp.appearance = darkAppearance
        let dark = Document.backgroundColor
        let darkComponents = Color(dark)
        XCTAssertNotEqual(light, dark)
        XCTAssertNotEqual(lightComponents, darkComponents)
        XCTAssertEqual(Color(light), lightComponents)

        NSApp.appearance = lightAppearance
        XCTAssertEqual(Document.backgroundColor, light)
        XCTAssertEqual(Color(Document.backgroundColor), lightComponents)
        XCTAssertEqual(Color(dark), darkComponents)
    }

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
            ("print \"hello\"", true),
            ("", false),
            ("print \"\"", false),
        ] {
            let viewController = MockViewController()
            let document = ViewMockDocument(viewController: viewController)
            viewController.document = document
            viewController.showConsole = true
            viewController.appendLog("Previous output")
            viewController.consoleVisibilityChanges = []
            let completed = expectation(description: "Reload finishes")
            viewController.onRenderComplete = { completed.fulfill() }
            document.sourceString = source
            document.didUpdateSource()
            let progress = try XCTUnwrap(document.loadingProgress)
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
        document.error = .runtimeError(RuntimeError(
            .custom("Original evaluation error"),
            at: document.sourceString.startIndex ..< document.sourceString.endIndex
        ))
        document.updateViews()
        let originalMessage = try XCTUnwrap(viewController.errorMessage)

        let completed = expectation(description: "Corrected source finishes rendering")
        viewController.onRenderComplete = { completed.fulfill() }
        document.sourceString = "cube {}"
        document.didUpdateSource()
        document.updateViews()
        XCTAssertNotNil(document.error)
        XCTAssertEqual(viewController.errorMessage, originalMessage)
        XCTAssertEqual(document.errorMessage, originalMessage)

        let progress = try XCTUnwrap(document.loadingProgress)
        await fulfillment(of: [completed], timeout: 5)
        document.updateViews()
        XCTAssertTrue(progress.didSucceed)
        XCTAssertNil(document.error)
        XCTAssertNil(viewController.errorMessage)
        XCTAssertNotNil(document.scene)
    }

    func testSourceUpdateClearsSyntaxErrorsAfterParsing() throws {
        for source in ["cube {", "\""] {
            let viewController = MockViewController()
            let document = ViewMockDocument(viewController: viewController)
            viewController.document = document
            document.sourceString = source
            XCTAssertThrowsError(try parse(source)) { error in
                document.error = ProgramError(error)
            }
            document.updateViews()
            let originalMessage = try XCTUnwrap(viewController.errorMessage)

            document.sourceString = ""
            XCTAssertNotNil(document.error)
            XCTAssertEqual(viewController.errorMessage, originalMessage)

            document.didParseSource()
            XCTAssertNil(document.error)
            XCTAssertNil(document.errorMessage)
            XCTAssertNil(viewController.errorMessage)
        }
    }

    func testParsingSuccessPreservesImportedSyntaxErrors() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "import \"example.shape\""
        let source = "cube {"
        XCTAssertThrowsError(try parse(source)) { error in
            document.error = .runtimeError(RuntimeError(
                .importError(ProgramError(error), for: nil, in: source),
                at: document.sourceString.startIndex ..< document.sourceString.endIndex
            ))
        }
        document.updateViews()
        let originalError = try XCTUnwrap(document.error)
        let originalMessage = try XCTUnwrap(viewController.errorMessage)
        document.didParseSource()
        XCTAssertEqual(document.error, originalError)
        XCTAssertEqual(viewController.errorMessage, originalMessage)
    }

    func testSourceUpdatePreservesErrorDuringProgressAndReplacesItOnFailure() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "cube {"
        let originalError = ProgramError(
            CSGImportError(message: "Original error", line: 1, column: 1),
            in: document.sourceString
        )
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

        let replacementError = ProgramError(
            CSGImportError(message: "Replacement error", line: 1, column: 1),
            in: document.sourceString
        )
        progress.setStatus(.failure(replacementError))
        XCTAssertEqual(document.error, replacementError)
        XCTAssertEqual(viewController.errorMessage, replacementError.message(with: document.sourceString))
        XCTAssertTrue(try XCTUnwrap(viewController.errorMessage).string.contains("sphere {\n^"))
        XCTAssertNotEqual(viewController.errorMessage, originalMessage)
    }

    func testOutdatedSourceErrorDoesNotReplaceDisplayedError() throws {
        let viewController = MockViewController()
        let document = ViewMockDocument(viewController: viewController)
        viewController.document = document
        document.sourceString = "cube {"
        let originalError = ProgramError(
            CSGImportError(message: "Original error", line: 1, column: 1),
            in: document.sourceString
        )
        document.error = originalError
        document.updateViews()
        let originalMessage = try XCTUnwrap(viewController.errorMessage)
        document.didUpdateSource()
        let progress = try XCTUnwrap(document.loadingProgress)

        document.sourceString = "cube {}"
        let outdatedError = ProgramError(CSGImportError(message: "Outdated error", line: 1, column: 1), in: "cube {")
        progress.setStatus(.failure(outdatedError))
        document.updateViews()
        XCTAssertEqual(document.error, originalError)
        XCTAssertEqual(viewController.errorMessage, originalMessage)
    }

    func testErrorOverlayReflowsWhenTextViewResizes() {
        let controller = DocumentViewController()
        _ = controller.view
        let source = String(repeating: "x", count: 60)
        let error = ProgramError.runtimeError(RuntimeError(
            .custom("Invalid expression"), at: source.startIndex ..< source.endIndex
        ))
        controller.errorTextView.setFrameSize(NSSize(width: 220, height: 400))
        controller.errorMessage = error.message(with: source)
        let narrow = controller.errorTextView.string
        controller.errorTextView.setFrameSize(NSSize(width: 700, height: 400))
        let wide = controller.errorTextView.string
        XCTAssertNotEqual(narrow, wide)
        XCTAssertTrue(wide.contains(source))
        controller.errorTextView.setFrameSize(NSSize(width: 220, height: 400))
        XCTAssertEqual(controller.errorTextView.string, narrow)
    }

    func testErrorOverlayReplacesExcerptAtSameWidth() throws {
        let controller = DocumentViewController()
        _ = controller.view
        controller.errorTextView.setFrameSize(NSSize(width: 240, height: 400))
        for symbol in ["firstUnknown", "secondUnknown"] {
            let source = String(repeating: "cube ", count: 20) + symbol
            let range = try XCTUnwrap(source.range(of: symbol))
            let error = ProgramError.runtimeError(RuntimeError(.custom("Invalid expression"), at: range))
            controller.setError(error, message: error.message(with: source))
            let rendered = controller.errorTextView.string
            XCTAssertTrue(rendered.contains(symbol))
            XCTAssertTrue(rendered.contains("^"))
            if symbol == "secondUnknown" {
                XCTAssertFalse(rendered.contains("firstUnknown"))
            }
        }
        controller.setError(nil, message: nil)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(try XCTUnwrap(controller.errorTextView.enclosingScrollView).isHidden)
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
