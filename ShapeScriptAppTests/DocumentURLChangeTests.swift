//
//  DocumentURLChangeTests.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 19/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import SceneKit
import XCTest

private typealias URLChangeMockDocument = MockDocument<URLChangeMockViewController>

private final class URLChangeMockViewController: DocumentViewControllerProtocol, @unchecked Sendable {
    static let documentBackgroundColor = Color.clear

    weak var document: URLChangeMockDocument?
    let scnScene = SCNScene()
    var renderTimer: Timer?
    let scnView = SCNView()
    let errorTextView = OSTextView()
    let grantAccessButton = OSButton()
    var isQuickLook = false
    let cameraNode = SCNNode()
    var axesNode: SCNNode?
    var errorMessage: NSAttributedString?
    var isLoading = true
    var renderProgress: Double?
    var showConsole = false
    var showAxes = true
    var isOrthographic = true
    var camera = Viewer.Camera.default
    var background: MaterialProperty?
    var selectedGeometry: Geometry?
    var warningPresentation: WarningQueue.Presentation?
    var warningMessages = [String]()
    var automaticallyDismissWarnings = true
    var onNextWarning: (@MainActor @Sendable () -> Void)?
    var onDismissWarnings: (@MainActor @Sendable () -> Void)?

    func presentError(_: Error, completionHandler: (() -> Void)?) -> Bool {
        completionHandler?()
        return true
    }

    func showWarning(
        _ message: NSAttributedString,
        onNext: @escaping @MainActor @Sendable () -> Void,
        onDismissAll: @escaping @MainActor @Sendable () -> Void
    ) {
        warningMessages.append(message.string)
        onNextWarning = onNext
        onDismissWarnings = onDismissAll
        if automaticallyDismissWarnings {
            onDismissAll()
        }
    }

    func hideWarning() {
        onNextWarning = nil
        onDismissWarnings = nil
    }

    var hasLog = false
    func clearLog() { hasLog = false }
    func appendLog(_ text: String) { hasLog = hasLog || !text.isEmpty }
    func updateModals() {}
    func copyCamera() {}
}

@MainActor
final class DocumentURLChangeTests: XCTestCase {
    func testZUpDefaultsFollowDocumentType() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shape = URLChangeMockDocument(fileURL: directory.appendingPathComponent("model.shape"))
        let csg = URLChangeMockDocument(fileURL: directory.appendingPathComponent("model.CSG"))
        try Data().write(to: XCTUnwrap(shape.documentFileURL))
        try Data().write(to: XCTUnwrap(csg.documentFileURL))
        XCTAssertFalse(shape.zUp)
        XCTAssertTrue(csg.zUp)
    }

    func testZUpCameraDirectionsAndFraming() throws {
        let front = Viewer.Camera(type: .front, zUp: true)
        XCTAssertEqual(front.direction.y, 1, accuracy: 1e-8)
        XCTAssertEqual(Vector.unitY.rotated(by: front.orientation).z, 1, accuracy: 1e-8)
        let top = Viewer.Camera(type: .top, zUp: true)
        XCTAssertEqual(top.direction.z, -1, accuracy: 1e-8)
        let left = Viewer.Camera(type: .left, zUp: true)
        XCTAssertEqual(left.direction.x, 1, accuracy: 1e-8)
        let scene = try Scene(csgString: "cube([2,4,10],true);", isCancelled: { false })
        XCTAssertTrue(scene.zUp)
        let yUpScene = scene.with(zUp: false)
        XCTAssertFalse(yUpScene.zUp)
        XCTAssertTrue(yUpScene.children[0] === scene.children[0])
        XCTAssertTrue(scene.with(zUp: true) === scene)
        XCTAssertNotEqual(scene, yUpScene)
        XCTAssertFalse(Scene.empty.zUp)
        XCTAssertTrue(scene.build { false })
        let options = ExportOptions(
            convertToZUp: true,
            camera: "Front",
            width: 200,
            height: 200
        )
        let camera = try scene.exportCamera(with: options, fallbackSize: (200, 200), camera: nil)
        let orientation = try XCTUnwrap(camera.orientation)
        XCTAssertEqual(Vector.unitY.rotated(by: orientation).z, 1, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(camera.position).y, -12, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(camera.scale).x, 10 / 1.8, accuracy: 1e-8)
        XCTAssertEqual(scene.geometryRotation(for: options), .identity)
        let yUpOptions = ExportOptions(convertToZUp: true, camera: nil, width: nil, height: nil)
        for zUp in [false, true] {
            let fallback = try scene.with(zUp: zUp).exportCamera(
                with: yUpOptions,
                fallbackSize: (200, 200),
                camera: nil
            )
            XCTAssertEqual(fallback.orientation, Viewer.Camera(type: .front, zUp: zUp).orientation)
        }
        XCTAssertEqual(
            Vector.unitY.rotated(by: scene.with(zUp: false).geometryRotation(for: yUpOptions)).z,
            1,
            accuracy: 1e-8
        )
    }

    func testDefaultCameraLooksDownOnFlatModelsInEitherUpAxis() {
        for zUp in [false, true] {
            for (size, expected) in [
                (Vector(10, 0, 20), CameraType.top),
                (Vector(10, 0.5, 20), .top),
                (Vector(10, 1, 20), .top),
                (Vector(10, 1.99, 20), .top),
                (Vector(10, 2, 20), .front),
                (Vector(10, 2.01, 20), .front),
                (Vector(10, 10, 10), .front),
                (Vector(100, 1, 0.1), .front),
                (Vector(10, 0, 0), .front),
            ] {
                let size = zUp ? Vector(size.x, size.z, size.y) : size
                let camera = Viewer.Camera(bounds: Bounds(.zero, size), zUp: zUp)
                XCTAssertEqual(camera.type, expected)
                XCTAssertEqual(camera.zUp, zUp)
            }
            XCTAssertEqual(Viewer.Camera(bounds: .empty, zUp: zUp).type, .front)
        }
    }

    func testFlatDocumentDefaultsRespectExplicitCameraSelections() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csg")
        let document = URLChangeMockDocument(fileURL: url)
        document.scene = try Scene(csgString: "cube([10,20,0.5]);", isCancelled: { false })
        document.updateCameras()
        XCTAssertEqual(document.camera.type, .top)
        XCTAssertTrue(document.camera.zUp)
        let frontIndex = try XCTUnwrap(document.cameras.firstIndex { $0.type == .front })
        XCTAssertTrue(document.selectCamera(at: frontIndex))
        document.updateCameras()
        XCTAssertEqual(document.camera.type, .front)
        let topIndex = try XCTUnwrap(document.cameras.firstIndex { $0.type == .top })
        XCTAssertTrue(document.selectCamera(at: topIndex))
        // Selecting the current automatic default should also persist that choice.
        let other = URLChangeMockDocument(fileURL: url.deletingPathExtension().appendingPathExtension("shape"))
        other.scene = try evaluate(parse("cube { size 10 0.5 20 }"), delegate: nil)
        other.updateCameras()
        XCTAssertEqual(other.camera.type, .top)
        XCTAssertTrue(other.selectCamera(at: topIndex))
        other.scene = try evaluate(parse("cube"), delegate: nil)
        other.updateCameras()
        XCTAssertEqual(other.camera.type, .top)
    }

    func testFlatSceneExportUsesTopUnlessCameraIsSpecified() throws {
        let scene = try Scene(csgString: "cube([10,20,0.5]); %cube(100);", isCancelled: { false })
        let options = ExportOptions(convertToZUp: false, camera: nil, width: nil, height: nil)
        let automatic = try scene.exportCamera(with: options, fallbackSize: (200, 200), camera: nil)
        XCTAssertEqual(automatic.orientation, Viewer.Camera(type: .top, zUp: true).orientation)
        let front = Viewer.Camera(type: .front, zUp: true)
        let explicit = try scene.exportCamera(with: options, fallbackSize: (200, 200), camera: front)
        XCTAssertEqual(explicit.orientation, front.orientation)
        let namedOptions = ExportOptions(convertToZUp: false, camera: "Front", width: nil, height: nil)
        let named = try scene.exportCamera(with: namedOptions, fallbackSize: (200, 200), camera: nil)
        XCTAssertEqual(named.orientation, front.orientation)
        let custom = try evaluate(parse("camera { orientation 10 20 30 }\ncube { size 10 0.5 20 }"), delegate: nil)
        let customExport = try custom.exportCamera(with: options, fallbackSize: (200, 200), camera: nil)
        XCTAssertEqual(customExport.orientation, custom.cameras.first?.worldTransform.rotation)
    }

    func testCameraUpAxisContextPreservesCustomOrientation() throws {
        let scene = try evaluate(parse("camera { orientation 10 20 30 }\ncube"), delegate: nil)
        let geometry = try XCTUnwrap(scene.cameras.first)
        let yUp = try scene.camera(named: "Custom")
        let zUpScene = scene.with(zUp: true)
        let zUp = try zUpScene.camera(named: "Custom")
        XCTAssertFalse(yUp.zUp)
        XCTAssertTrue(zUp.zUp)
        XCTAssertEqual(yUp.orientation, geometry.transform.rotation)
        XCTAssertEqual(zUp.orientation, yUp.orientation)
        XCTAssertEqual(zUp.direction, yUp.direction)
        XCTAssertEqual(zUp.upVector, .unitZ)
        XCTAssertEqual(yUp.upVector, .unitY)
        XCTAssertEqual(zUp.framingSize(Vector(2, 4, 10)), Vector(2, 10, 4))
        XCTAssertEqual(yUp.framingSize(Vector(2, 4, 10)), Vector(2, 4, 10))

        let options = ExportOptions(convertToZUp: false, camera: nil, width: nil, height: nil)
        let exported = try zUpScene.exportCamera(with: options, fallbackSize: (200, 200), camera: zUp)
        XCTAssertEqual(exported.orientation, geometry.worldTransform.rotation)
        let automatic = try zUpScene.exportCamera(with: options, fallbackSize: (200, 200), camera: nil)
        XCTAssertEqual(automatic.orientation, exported.orientation)
        let frontOverride = Viewer.Camera(type: .front, zUp: zUpScene.zUp)
        let front = try zUpScene.exportCamera(with: options, fallbackSize: (200, 200), camera: frontOverride)
        let orientation = try XCTUnwrap(front.orientation)
        XCTAssertEqual(Vector.unitY.rotated(by: orientation).z, 1, accuracy: 1e-8)
    }

    func testZUpViewerFrontCamera() throws {
        let (document, viewController) = queuedWarningDocument()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csg")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        document.documentFileURL = url
        viewController.cameraNode.camera = SCNCamera()
        document.scene = try Scene(csgString: "cube([2,4,10],true);", isCancelled: { false })
        XCTAssertTrue(try XCTUnwrap(document.scene).build { false })
        viewController.scnView.frame.size = CGSize(width: 200, height: 200)
        document.updateViews()
        XCTAssertTrue(try XCTUnwrap(document.scene).zUp)
        // The document type remains authoritative even if the scene is stale.
        document.scene = document.scene?.with(zUp: false)
        viewController.refreshAxesAndCamera()
        let geometry = try Geometry(viewController.cameraNode)
        XCTAssertEqual(Vector.unitY.rotated(by: geometry.transform.rotation).z, 1, accuracy: 1e-8)
        XCTAssertEqual(geometry.transform.translation.y, -12, accuracy: 1e-6)
    }

    func testNewDocumentTemplatesAreValid() throws {
        let shapeURL = try XCTUnwrap(Bundle.main.url(forResource: "Untitled", withExtension: "shape"))
        let shape = try evaluate(parse(String(contentsOf: shapeURL)), delegate: nil)
        XCTAssertTrue(shape.build { false })
        XCTAssertEqual(shape.geometry.objectCount, 3)
        let csgURL = try XCTUnwrap(Bundle.main.url(forResource: "Untitled", withExtension: "csg"))
        let csg = try Scene(csgString: String(contentsOf: csgURL), at: csgURL, isCancelled: { false })
        XCTAssertTrue(csg.build { false })
        XCTAssertTrue(csg.warnings.isEmpty)
        XCTAssertEqual(csg.geometry.objectCount, 3)
        let coneVertices = csg.geometry.merged().polygons.filter {
            ($0.material as? Material)?.color == .blue
        }.flatMap(\.vertices)
        XCTAssertFalse(coneVertices.isEmpty)
        XCTAssertTrue(coneVertices.contains { ($0.position - Vector(1.5, 0, 0.5)).length < 1e-8 })
        XCTAssertTrue(coneVertices.allSatisfy {
            abs($0.position.z + 0.5) < 1e-8 || ($0.position - Vector(1.5, 0, 0.5)).length < 1e-8
        })
    }

    private func queuedWarningDocument() -> (URLChangeMockDocument, URLChangeMockViewController) {
        let viewController = URLChangeMockViewController()
        viewController.automaticallyDismissWarnings = false
        let document = URLChangeMockDocument(viewController: viewController)
        viewController.document = document
        return (document, viewController)
    }

    func testWarningQueueShowsOneAtATimeWithProgressCounter() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second", "Third"])
        XCTAssertEqual(viewController.warningMessages, ["1/3 First"])
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningMessages.last, "2/3 Second")
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningMessages.last, "3/3 Third")
        viewController.onNextWarning?()
        XCTAssertEqual(document.warningQueue.current?.message, "First")
        XCTAssertEqual(viewController.warningMessages.last, "1/3 First")
        viewController.checkDocumentWarnings(["First", "Second", "Third"])
        XCTAssertEqual(viewController.warningMessages.count, 4)
    }

    func testQuickLookWarningsCycleDismissAndYieldToErrors() throws {
        let (document, viewController) = queuedWarningDocument()
        viewController.isQuickLook = true
        document.scene = try Scene(
            csgString: "surface(file=\"part.dat\"); resize([2,2,2]) cube(1);",
            isCancelled: { false }
        )
        let warnings = try XCTUnwrap(document.scene?.warnings)
        XCTAssertEqual(warnings.count, 2)
        viewController.checkDocumentWarnings()
        XCTAssertEqual(viewController.warningPresentation?.message, warnings[0])
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningPresentation?.message, warnings[1])
        viewController.setError(nil, message: NSAttributedString(string: "Error"))
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertNil(viewController.onNextWarning)
        viewController.setError(nil, message: nil)
        XCTAssertEqual(viewController.warningPresentation?.message, warnings[1])
        viewController.onDismissWarnings?()
        viewController.checkDocumentWarnings()
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertNil(document.warningQueue.current)
    }

    func testClosingWarningDismissesEntireQueueButNewWarningsStillAppear() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second", "Third"])
        viewController.onDismissWarnings?()
        XCTAssertNil(document.warningQueue.current)
        viewController.checkDocumentWarnings(["First", "Second", "Third"])
        XCTAssertEqual(viewController.warningMessages.count, 1)
        viewController.checkDocumentWarnings(["First", "Second", "Third", "New"])
        XCTAssertEqual(viewController.warningMessages.last, "New")
        XCTAssertEqual(viewController.warningMessages.count, 2)
    }

    func testSingleWarningCyclesUntilClosed() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["Only warning"])
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningMessages, ["Only warning", "Only warning"])
        XCTAssertEqual(document.warningQueue.current?.position, 1)
        viewController.onDismissWarnings?()
        viewController.checkDocumentWarnings(["Only warning"])
        XCTAssertNil(document.warningQueue.current)
    }

    func testErrorsTemporarilyHideWarningsWithoutChangingTheCycle() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second"])
        viewController.onNextWarning?()
        let oldNext = viewController.onNextWarning
        let oldDismiss = viewController.onDismissWarnings
        document.error = ProgramError(CSGImportError(message: "Invalid CSG", line: 1, column: 1))
        viewController.setError(document.error, message: NSAttributedString(string: "Invalid CSG"))
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertNil(viewController.onNextWarning)
        XCTAssertNil(viewController.onDismissWarnings)
        oldNext?()
        oldDismiss?()
        XCTAssertEqual(document.warningQueue.current?.message, "Second")
        viewController.checkDocumentWarnings(["First", "Second", "New"])
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertEqual(viewController.warningMessages.count, 2)
        document.error = nil
        // The error overlay may outlive the document's error while a reload is in progress.
        viewController.checkDocumentWarnings(["First", "Second", "New"])
        XCTAssertNil(viewController.warningPresentation)
        viewController.setError(nil, message: nil)
        XCTAssertEqual(viewController.warningMessages.last, "2/3 Second")
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningMessages.last, "3/3 New")
    }

    func testErrorsDoNotRestoreDismissedWarnings() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second"])
        viewController.onDismissWarnings?()
        viewController.setError(nil, message: NSAttributedString(string: "Error"))
        viewController.checkDocumentWarnings(["First", "Second"])
        viewController.setError(nil, message: nil)
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertNil(document.warningQueue.current)
        XCTAssertEqual(viewController.warningMessages.count, 1)
    }

    func testReloadUpdatesWarningQueueWithoutRestartingIt() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First (line 1, column 1)", "Second"])
        viewController.onNextWarning?()
        viewController.checkDocumentWarnings(["First (line 8, column 3)", "Second"])
        XCTAssertEqual(viewController.warningMessages.count, 2)
        viewController.checkDocumentWarnings(["New", "First (line 8, column 3)", "Second"])
        XCTAssertEqual(viewController.warningMessages.last, "2/3 Second")
        viewController.onNextWarning?()
        XCTAssertEqual(viewController.warningMessages.last, "3/3 New")
        XCTAssertEqual(document.warningQueue.current?.message, "New")
    }

    func testRepeatedWarningsRemainSeparateAcrossReloads() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings([
            "Repeated (line 1, column 1)", "Repeated (line 2, column 1)",
        ])
        XCTAssertEqual(document.warningQueue.current?.total, 2)
        viewController.onNextWarning?()
        viewController.checkDocumentWarnings([
            "Repeated (line 8, column 1)", "Repeated (line 9, column 1)",
        ])
        XCTAssertEqual(document.warningQueue.current?.message, "Repeated (line 9, column 1)")
        XCTAssertEqual(document.warningQueue.current?.position, 2)
        viewController.onNextWarning?()
        viewController.checkDocumentWarnings([
            "Repeated (line 8, column 1)", "Repeated (line 9, column 1)",
            "Repeated (line 10, column 1)",
        ])
        XCTAssertEqual(document.warningQueue.current?.message, "Repeated (line 8, column 1)")
        viewController.onNextWarning?()
        viewController.onNextWarning?()
        XCTAssertEqual(document.warningQueue.current?.message, "Repeated (line 10, column 1)")
        viewController.onDismissWarnings?()
        viewController.checkDocumentWarnings([
            "Repeated (line 11, column 1)", "Repeated (line 12, column 1)",
            "Repeated (line 13, column 1)",
        ])
        XCTAssertNil(document.warningQueue.current)
    }

    func testResolvedWarningsAreRemovedAndToastIsHidden() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second"])
        viewController.checkDocumentWarnings(["Second"])
        XCTAssertEqual(document.warningQueue.current?.message, "Second")
        XCTAssertEqual(viewController.warningMessages.last, "Second")
        viewController.checkDocumentWarnings([])
        XCTAssertNil(document.warningQueue.current)
        XCTAssertNil(viewController.warningPresentation)
        XCTAssertNil(viewController.onNextWarning)
    }

    func testOldWarningCallbacksCannotDismissReplacementWarnings() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second"])
        let oldNext = viewController.onNextWarning
        let oldDismiss = viewController.onDismissWarnings
        viewController.checkDocumentWarnings(["New"])
        oldNext?()
        oldDismiss?()
        XCTAssertEqual(document.warningQueue.current?.message, "New")
        XCTAssertEqual(viewController.warningMessages.last, "New")
    }

    func testWarningQueueResetStartsNewSessionAndRejectsOldCallbacks() {
        let (document, viewController) = queuedWarningDocument()
        viewController.checkDocumentWarnings(["First", "Second"])
        let oldDismiss = viewController.onDismissWarnings
        document.warningQueue.reset()
        viewController.checkDocumentWarnings(["First", "Second"])
        oldDismiss?()
        XCTAssertEqual(document.warningQueue.current?.message, "First")
        XCTAssertEqual(viewController.warningMessages.count, 2)
    }

    func testImportWarningsUseToastAndDismissalSuppressesRepeats() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("model.csg")
        try "color(\"red\") cube(1);".write(to: url, atomically: true, encoding: .utf8)
        let viewController = URLChangeMockViewController()
        let document = URLChangeMockDocument(fileURL: url, viewController: viewController)
        viewController.document = document
        document.scene = try Scene(csgString: String(contentsOf: url), at: url, isCancelled: { false })
        viewController.checkDocumentWarnings()
        XCTAssertEqual(
            viewController.warningMessages,
            try [XCTUnwrap(document.scene?.warnings.joined(separator: "\n\n"))]
        )
        viewController.checkDocumentWarnings()
        XCTAssertEqual(viewController.warningMessages.count, 1)
        let original = try XCTUnwrap(document.scene?.warnings.first)
        let moved = original.replacingOccurrences(of: "line 1, column 1", with: "line 8, column 3")
        viewController.checkDocumentWarnings([moved])
        XCTAssertEqual(viewController.warningMessages.count, 1)
        viewController.checkDocumentWarnings([moved, "New warning"])
        XCTAssertEqual(viewController.warningMessages.last, "New warning")
        XCTAssertEqual(viewController.warningMessages.count, 2)
        viewController.checkDocumentWarnings([])
        viewController.checkDocumentWarnings([original, "New warning"])
        XCTAssertEqual(viewController.warningMessages.count, 2)

        let reopenedViewController = URLChangeMockViewController()
        let reopened = URLChangeMockDocument(fileURL: url, viewController: reopenedViewController)
        reopenedViewController.document = reopened
        reopened.scene = document.scene
        reopenedViewController.checkDocumentWarnings()
        XCTAssertEqual(reopenedViewController.warningMessages, [original])

        viewController.isQuickLook = true
        viewController.checkDocumentWarnings(["Another warning"])
        XCTAssertEqual(viewController.warningMessages.count, 3)
        XCTAssertEqual(viewController.warningMessages.last, "Another warning")
    }

    func testVersionWarningDismissalIsAlsoSessionOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("model.shape")
        try "cube".write(to: url, atomically: true, encoding: .utf8)
        let viewController = URLChangeMockViewController()
        let document = URLChangeMockDocument(fileURL: url, viewController: viewController)
        viewController.document = document
        document.formatVersion = "99.0.0"
        document.clientVersion = "99.0.0"
        viewController.checkDocumentWarnings()
        viewController.checkDocumentWarnings()
        XCTAssertEqual(viewController.warningMessages.count, 1)
        XCTAssertTrue(viewController.warningMessages[0].contains("newer version"))
        XCTAssertEqual(document.clientVersion, "99.0.0")

        let reopenedViewController = URLChangeMockViewController()
        let reopened = URLChangeMockDocument(fileURL: url, viewController: reopenedViewController)
        reopenedViewController.document = reopened
        reopenedViewController.checkDocumentWarnings()
        XCTAssertEqual(reopenedViewController.warningMessages, viewController.warningMessages)
    }

    #if os(macOS)
    func testWarningTextClickDoesNotAdvanceForSelectionOrDrag() async throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = WarningTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: "1/6 Warning", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
        ]))
        window.contentView?.addSubview(textView)
        let actions = WarningButtonActions()
        textView.onNext = { actions.next += 1 }
        func event(_ clickCount: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 10, y: 10),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: 1
            ))
        }
        let click = try event(1)
        textView.completeMouseInteraction(with: click, mouseUpLocation: click.locationInWindow)
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        try textView.completeMouseInteraction(with: event(2), mouseUpLocation: click.locationInWindow)
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
        XCTAssertEqual(actions.next, 0)
        let font = try XCTUnwrap(textView.attributedString().attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        textView.completeMouseInteraction(with: click, mouseUpLocation: click.locationInWindow, hadSelection: true)
        XCTAssertEqual(textView.selectedRange().length, 0)
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
        XCTAssertEqual(actions.next, 0)
        textView.completeMouseInteraction(with: click, mouseUpLocation: CGPoint(x: 30, y: 10))
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
        XCTAssertEqual(actions.next, 0)
        textView.completeMouseInteraction(with: click, mouseUpLocation: click.locationInWindow)
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
        XCTAssertEqual(actions.next, 1)
    }

    func testQuickLookResizeFramesCameraBeforeNextLoadingUpdate() throws {
        let document = Document()
        document.scene = try Scene(csgString: "cube([40, 20, 10]);", isCancelled: { false })
        let viewController = DocumentViewController()
        viewController.document = document
        viewController.isQuickLook = true
        viewController.isLoading = true
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = viewController
        viewController.view.layoutSubtreeIfNeeded()
        viewController.refreshScene()

        for size in [NSSize(width: 300, height: 600), NSSize(width: 800, height: 400)] {
            window.setContentSize(size)
            viewController.view.layoutSubtreeIfNeeded()
            let position = viewController.cameraNode.position
            let scale = viewController.cameraNode.camera?.orthographicScale
            viewController.refreshScene()
            XCTAssertEqual(viewController.cameraNode.position.x, position.x, accuracy: 0.001)
            XCTAssertEqual(viewController.cameraNode.position.y, position.y, accuracy: 0.001)
            XCTAssertEqual(viewController.cameraNode.position.z, position.z, accuracy: 0.001)
            XCTAssertEqual(viewController.cameraNode.camera?.orthographicScale, scale)
        }
    }

    func testQuickLookDisplaysNativeWarningBanner() throws {
        let document = Document()
        document.scene = try Scene(csgString: "surface(file=\"part.dat\");", isCancelled: { false })
        let warning = try XCTUnwrap(document.scene?.warnings.first)
        let viewController = DocumentViewController()
        viewController.document = document
        viewController.isQuickLook = true
        viewController.view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        viewController.checkDocumentWarnings()
        viewController.view.layoutSubtreeIfNeeded()
        let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        let label = try XCTUnwrap(banner.subviews.compactMap { $0 as? WarningTextView }.first)
        XCTAssertEqual(label.string, warning)
        XCTAssertGreaterThan(banner.frame.height, 0)
    }

    func testWarningBannerAllowsWindowToShrinkAndWrapsText() throws {
        for isQuickLook in [false, true] {
            let document = Document()
            let viewController = DocumentViewController()
            viewController.document = document
            viewController.isQuickLook = isQuickLook
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentViewController = viewController
            viewController.checkDocumentWarnings(["This document contains unsupported geometry and may be incomplete."])
            let presentation = try XCTUnwrap(viewController.warningPresentation)
            let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
            let label = try XCTUnwrap(banner.subviews.compactMap { $0 as? WarningTextView }.first)
            viewController.view.layoutSubtreeIfNeeded()
            let wideHeight = label.frame.height
            window.setContentSize(NSSize(width: 200, height: 480))
            viewController.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(viewController.view.bounds.width, 200, accuracy: 1)
            XCTAssertLessThanOrEqual(banner.frame.width, 160)
            XCTAssertFalse(banner.isHidden)
            XCTAssertGreaterThan(label.frame.height, wideHeight)
            XCTAssertEqual(viewController.warningPresentation, presentation)
            XCTAssertEqual(document.warningQueue.current, presentation)
            window.setContentSize(NSSize(width: 900, height: 480))
            viewController.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(viewController.view.bounds.width, 900, accuracy: 1)
            XCTAssertEqual(banner.frame.width, 640, accuracy: 1)
        }
    }

    func testNativeCSGTextWarningsAdvance() async throws {
        let source = (0 ..< 6).map { "text(\"\($0)\", spacing=2);" }.joined(separator: "\n")
        let document = Document()
        document.scene = try Scene(csgString: source, isCancelled: { false })
        let warnings = try XCTUnwrap(document.scene?.warnings)
        XCTAssertEqual(warnings.count, 6)
        let viewController = DocumentViewController()
        viewController.document = document
        viewController.view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        viewController.checkDocumentWarnings()
        XCTAssertEqual(viewController.warningPresentation?.total, 6)
        for (index, warning) in warnings.enumerated() {
            XCTAssertEqual(viewController.warningPresentation?.message, warning)
            XCTAssertEqual(viewController.warningPresentation?.position, index + 1)
            viewController.view.layoutSubtreeIfNeeded()
            let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
            let label = try XCTUnwrap(banner.subviews.compactMap { $0 as? WarningTextView }.first)
            XCTAssertEqual(label.string, "\(index + 1)/6 \(warning)")
            let counterFont = try XCTUnwrap(label.attributedString().attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: counterFont).contains(.boldFontMask))
            let messageFont = try XCTUnwrap(label.attributedString().attribute(
                .font,
                at: 4,
                effectiveRange: nil
            ) as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: messageFont).contains(.boldFontMask))
            XCTAssertTrue(label.isSelectable)
            label.setSelectedRange(NSRange(location: 0, length: 3))
            let selectedCounterFont = try XCTUnwrap(label.attributedString().attribute(
                .font, at: 0, effectiveRange: nil
            ) as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: selectedCounterFont).contains(.boldFontMask))
            XCTAssertEqual(viewController.warningPresentation?.message, warning)
            let textPoint = label.convert(
                CGPoint(x: label.bounds.midX, y: label.bounds.midY),
                to: banner.superview
            )
            XCTAssertTrue(banner.hitTest(textPoint) === label)
            let nextButton = try XCTUnwrap(banner.subviews.compactMap { $0 as? NSButton }
                .first { $0.toolTip == "Next warning" })
            nextButton.performClick(nil)
            for _ in 0 ..< 200 {
                if viewController.warningPresentation?.message != warning {
                    break
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        XCTAssertEqual(viewController.warningPresentation?.message, warnings.first)
        XCTAssertEqual(viewController.warningPresentation?.position, 1)
        let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        let closeButton = try XCTUnwrap(banner.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == "Dismiss all warnings" })
        closeButton.performClick(nil)
        for _ in 0 ..< 200 {
            if viewController.warningPresentation == nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        viewController.checkDocumentWarnings()
        XCTAssertNil(viewController.warningPresentation)
    }

    func testNativeWarningTapShowsNextQueuedWarning() async throws {
        let document = Document()
        let viewController = DocumentViewController()
        viewController.document = document
        viewController.view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        viewController.checkDocumentWarnings(["First warning", "Second warning"])
        viewController.view.layoutSubtreeIfNeeded()
        let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        let nextButton = try XCTUnwrap(banner.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == "Next warning" })
        nextButton.performClick(nil)
        for _ in 0 ..< 200 {
            if viewController.warningPresentation?.message == "Second warning" {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewController.warningPresentation?.text, "2/2 Second warning")
        viewController.view.layoutSubtreeIfNeeded()
        let nextBanner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        XCTAssertFalse(nextBanner === banner)
        let label = try XCTUnwrap(nextBanner.subviews.compactMap { $0 as? WarningTextView }.first)
        XCTAssertEqual(label.string, "2/2 Second warning")
        XCTAssertGreaterThan(label.frame.width, 50)
        viewController.hideWarning()
    }

    func testNativeWarningButtonsAdvanceAndDismissSeparately() async throws {
        let viewController = DocumentViewController()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let actions = WarningButtonActions()
        func showWarning() {
            viewController.showWarning(NSAttributedString(string: "1/2 Example"), onNext: {
                actions.next += 1
            }, onDismissAll: {
                actions.dismissAll += 1
            })
            viewController.view.layoutSubtreeIfNeeded()
        }
        showWarning()
        let banner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        let label = try XCTUnwrap(banner.subviews.compactMap { $0 as? WarningTextView }.first)
        XCTAssertEqual(label.string, "1/2 Example")
        XCTAssertGreaterThan(label.frame.width, 50)
        XCTAssertGreaterThan(label.frame.height, 10)
        let nextButton = try XCTUnwrap(banner.subviews.compactMap { $0 as? NSButton }
            .first { $0.toolTip == "Next warning" })
        let point = nextButton.convert(
            CGPoint(x: 20, y: nextButton.bounds.midY),
            to: banner.superview
        )
        XCTAssertTrue(banner.hitTest(point) === nextButton)
        nextButton.performClick(nil)
        for _ in 0 ..< 200 {
            if actions.next == 1 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(actions.next, 1)
        XCTAssertEqual(actions.dismissAll, 0)
        showWarning()
        let secondBanner = try XCTUnwrap(viewController.view.subviews.last as? NSVisualEffectView)
        let closeButton = try XCTUnwrap(secondBanner.subviews.compactMap { $0 as? NSButton }.first {
            $0.toolTip == "Dismiss all warnings"
        })
        closeButton.performClick(nil)
        for _ in 0 ..< 200 {
            if actions.dismissAll == 1 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(actions.next, 1)
        XCTAssertEqual(actions.dismissAll, 1)
        viewController.hideWarning()
    }

    func testOpeningCSGDocumentUsesCSGParser() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("model.csg")
        try "cube([2,3,4]);".write(to: url, atomically: true, encoding: .utf8)
        let document = try Document(contentsOf: url, ofType: "org.openscad.csg")
        defer { document.close() }
        let expectedBounds = Bounds(.zero, [2, 3, 4])
        for _ in 0 ..< 200 {
            // The background status can finish before its main-actor observer delivers the scene.
            if document.loadingProgress?.didSucceed == true,
               document.scene?.geometry.merged().bounds == expectedBounds
            {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(document.loadingProgress?.didSucceed, true)
        XCTAssertNil(document.error)
        XCTAssertEqual(document.scene?.geometry.merged().bounds, expectedBounds)
    }
    #endif

    func testCSGDocumentLoadingAndErrors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("model.csg")
        let cases: [(String, String?, Int, Int)] = [
            ("cube([2,3,4]);", nil, 1, 1),
            ("cube([1,2]);", "Expected a CSG vector with 3 components", 1, 1),
            ("// comment\n\n  cubee(1);", "Unknown CSG operation 'cubee'", 3, 3),
            ("\n    cube(szie=2);", "Unknown CSG argument 'szie'", 2, 5),
            ("\n  @", "Unsupported CSG token '@'", 2, 3),
        ]
        for (source, errorMessage, line, column) in cases {
            let succeeds = errorMessage == nil
            let data = Data(source.utf8)
            try data.write(to: url)
            let document = URLChangeMockDocument(fileURL: url)
            try document.load(data, fileURL: url)
            document.didUpdateSource()
            for _ in 0 ..< 200 {
                if document.loadingProgress?.inProgress == false, succeeds || document.error != nil {
                    break
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(document.loadingProgress?.didSucceed, succeeds)
            if succeeds {
                XCTAssertEqual(document.scene?.geometry.merged().bounds, Bounds(.zero, [2, 3, 4]))
                XCTAssertNil(document.error)
            } else {
                XCTAssertTrue(try document.error?.message.contains(XCTUnwrap(errorMessage)) == true)
                XCTAssertNil(document.warningQueue.current)
                let (range, errorSource) = try XCTUnwrap(document.error?.rangeAndSource(with: source))
                XCTAssertEqual(errorSource, source)
                let position = errorSource.lineAndColumn(at: range.lowerBound)
                XCTAssertEqual(position.line, line)
                XCTAssertEqual(position.column, column)
                XCTAssertNotNil(document.error?.errorLineAndRange(with: source))
            }
            document.loadingProgress?.cancel()
        }
    }

    func testSourceDocumentEditability() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, editable) in [
            ("model.shape", true),
            ("model.csg", true),
            ("model.CSG", true),
            ("model.stl", false),
        ] {
            let url = directory.appendingPathComponent(name)
            try "".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertTrue(FileManager.default.isWritableFile(atPath: url.path))
            let document = URLChangeMockDocument(fileURL: url)
            XCTAssertEqual(document.isEditable, editable)
        }
    }

    func testRefreshAfterDocumentURLChangeUpdatesMonitorViewsAndCallbacks() throws {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let oldURL = directoryURL.appendingPathComponent("Old.shape")
        let newURL = directoryURL.appendingPathComponent("New.shape")
        try "cube".write(to: oldURL, atomically: true, encoding: .utf8)
        try "sphere".write(to: newURL, atomically: true, encoding: .utf8)

        let monitor = try XCTUnwrap(FileMonitor(oldURL) { _ in })
        let viewController = URLChangeMockViewController()
        let document = URLChangeMockDocument(
            fileURL: newURL,
            fileMonitor: monitor,
            viewController: viewController
        )
        viewController.document = document
        document.scene = .empty
        document.loadingProgress = nil

        var didUpdateChrome = false
        var relatedSourceURL: URL?
        document.refreshAfterDocumentURLChange(
            updateDocumentChrome: {
                didUpdateChrome = true
            },
            updateRelatedSourceViews: {
                relatedSourceURL = $0
            }
        )

        XCTAssertEqual(monitor.url, newURL)
        XCTAssertTrue(didUpdateChrome)
        XCTAssertEqual(relatedSourceURL, newURL)
        XCTAssertFalse(viewController.isLoading)
        XCTAssertFalse(viewController.showAxes)
        XCTAssertFalse(viewController.isOrthographic)
        XCTAssertNotNil(viewController.geometry)
    }
}

#if os(macOS)
@MainActor
private final class WarningButtonActions {
    var next = 0
    var dismissAll = 0
}
#endif
