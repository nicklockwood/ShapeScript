//
//  DocumentViewControllerProtocol+View.swift
//  ShapeScriptApp
//
//  Created by Nick Lockwood on 09/09/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript

@MainActor
extension DocumentViewControllerProtocol {
    var geometry: Geometry? {
        document?.scene?.geometry
    }

    func didRefreshScene() {}
    func didRefreshCamera() {}
    func didRefreshOrthographic() {}
    func didResetView() {}

    var backgroundColor: OSColor {
        Document.backgroundColor
    }

    var isBrightBackground: Bool {
        let color = Color(backgroundColor)
        let luminance = background?.averageLuminance(over: color) ?? color.toLinear().luminance
        return luminance > Color.gray.toLinear().luminance
    }

    var interfaceColor: OSColor {
        isBrightBackground ? .black : .white
    }

    var visibleBounds: Bounds {
        document?.scene?.visibleBounds ?? .empty
    }

    func checkDocumentWarnings(_ warnings: [String]? = nil) {
        guard let document else {
            return
        }
        let versionWarning: String?
        if (document.formatVersion ?? ShapeScript.version) > ShapeScript.version {
            let clientVersion = document.clientVersion.map { " (\($0))" } ?? ""
            versionWarning = """
            \(document.fileName) was last edited with a newer version of \
            ShapeScript\(clientVersion) and may not be fully compatible with this version.
            """
        } else {
            versionWarning = nil
        }
        document.warningQueue.update(warnings ?? document.scene?.warnings ?? [], versionWarning: versionWarning)
        presentQueuedWarning()
    }

    private func presentQueuedWarning() {
        guard let document else {
            return
        }
        guard document.error == nil, errorMessage == nil else {
            warningPresentation = nil
            hideWarning()
            return
        }
        let presentation = document.warningQueue.current
        guard presentation != warningPresentation else { return }
        warningPresentation = presentation
        guard let presentation else {
            hideWarning()
            return
        }
        #if os(macOS)
        let fontSize: CGFloat = 13
        #else
        let fontSize: CGFloat = 14
        #endif
        let message = NSMutableAttributedString(string: presentation.text, attributes: [
            .font: OSFont.systemFont(ofSize: fontSize, weight: .medium),
        ])
        if presentation.total > 1 {
            message.addAttribute(
                .font,
                value: OSFont.systemFont(ofSize: fontSize, weight: .bold),
                range: NSRange(
                    location: 0,
                    length: "\(presentation.position)/\(presentation.total)".utf16.count
                )
            )
        }
        showWarning(message, onNext: { [weak self, weak document] in
            guard let self, let document, self.document === document,
                  document.error == nil, errorMessage == nil,
                  document.warningQueue.advance(presentation.id)
            else { return }
            warningPresentation = nil
            presentQueuedWarning()
        }, onDismissAll: { [weak self, weak document] in
            guard let self, let document, self.document === document,
                  document.error == nil, errorMessage == nil
            else { return }
            let dismissesVersionWarning = document.warningQueue.hasVersionWarning
            guard document.warningQueue.dismissAll(presentation.id) else { return }
            warningPresentation = nil
            if dismissesVersionWarning, !isQuickLook {
                document.markUpdatedWithCurrentVersion()
            }
        })
    }

    func setError(_ error: ProgramError?, message: NSAttributedString?) {
        switch error?.type ?? .evaluation {
        case .evaluation:
            errorTextView.backgroundColor = OSColor(red: 0.8, green: 0, blue: 0, alpha: 0.8)
            grantAccessButton.isHidden = true
        case .fileAccess:
            errorTextView.backgroundColor = OSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
            grantAccessButton.isHidden = false
        }
        errorMessage = message
        if error != nil || message != nil {
            warningPresentation = nil
            hideWarning()
        } else {
            presentQueuedWarning()
        }
    }

    var cameraHasMoved: Bool {
        guard renderer is SceneKitRenderer else {
            return false
        }
        return sceneKitRenderer.cameraHasMoved
    }

    var viewCenter: Vector {
        showAxes ? .zero : visibleBounds.center
    }

    func resetView() {
        defer { didResetView() }
        guard renderer is SceneKitRenderer else {
            return
        }
        sceneKitRenderer.resetCamera(
            camera: camera,
            visibleBounds: visibleBounds,
            showAxes: showAxes
        )
    }

    func refreshView() {
        guard renderer is SceneKitRenderer else {
            return
        }
        sceneKitRenderer.refreshView()
    }

    func refreshScene() {
        defer { didRefreshScene() }
        if geometry == nil {
            selectedGeometry = nil
        }
        if renderer is SceneKitRenderer {
            sceneKitRenderer.refreshGeometry(
                geometry,
                selectedGeometry: selectedGeometry,
                showAxes: showAxes,
                isQuickLook: isQuickLook,
                camera: camera,
                isOrthographic: isOrthographic,
                visibleBounds: visibleBounds,
                interfaceColor: interfaceColor
            )
            return
        }
        if #available(macOS 15.0, iOS 18.0, visionOS 1.0, *),
           document?.loadingProgress?.inProgress != true,
           let scene = document?.scene
        {
            renderer.prepare(
                scene,
                options: scene.outputOptions(
                    for: camera.settings,
                    backgroundColor: Color(backgroundColor),
                    wireframe: document?.showWireframe ?? false
                )
            )
        }
    }

    func selectGeometry(at location: CGPoint) {
        guard renderer is SceneKitRenderer else {
            return
        }
        selectedGeometry = geometry.flatMap {
            sceneKitRenderer.selectGeometry(at: location, in: $0)
        }
    }

    func selectGeometry(_ scnNode: SCNNode?) {
        guard renderer is SceneKitRenderer else {
            selectedGeometry = nil
            return
        }
        selectedGeometry = sceneKitRenderer.selectGeometry(scnNode, in: geometry)
    }

    func selectableGeometries(at location: CGPoint) -> [Geometry] {
        guard renderer is SceneKitRenderer else {
            return []
        }
        return geometry.map { sceneKitRenderer.selectableGeometries(at: location, in: $0) } ?? []
    }

    func selectionMenuContext(at location: CGPoint) -> SelectionMenuContext? {
        guard let document else {
            return nil
        }
        let geometries = selectableGeometries(at: location)
        let entries = geometries.isEmpty ?
            document.selectionMenuEntries :
            document.selectionMenuEntries(for: geometries)
        guard !entries.isEmpty else {
            return nil
        }
        return SelectionMenuContext(
            entries: entries,
            lazySubmenus: geometries.isEmpty
        )
    }

    func refreshGeometry() { refreshScene() }
    func resetCamera() {
        refreshAxesAndCamera()
        resetView()
    }

    func refreshOrthographic() {
        defer { didRefreshOrthographic() }
        guard renderer is SceneKitRenderer else {
            refreshAxesAndCamera()
            return
        }
        sceneKitRenderer.refreshOrthographic(
            camera: camera,
            isOrthographic: isOrthographic,
            isQuickLook: isQuickLook
        )
    }

    func updateAxes() {
        refreshAxesAndCamera()
    }

    func updateCamera() {
        refreshAxesAndCamera()
    }

    func refreshAxesAndCamera() {
        defer { didRefreshCamera() }
        if renderer is SceneKitRenderer {
            sceneKitRenderer.updateAxesAndCamera(
                showAxes: showAxes,
                isQuickLook: isQuickLook,
                camera: camera,
                isOrthographic: isOrthographic,
                visibleBounds: visibleBounds,
                interfaceColor: interfaceColor
            )
            return
        }
        if #available(macOS 15.0, iOS 18.0, visionOS 1.0, *),
           let realityKitRenderer = renderer as? RealityKitRenderer
        {
            realityKitRenderer.updateAxesAndCamera(
                showAxes: showAxes,
                isQuickLook: isQuickLook,
                camera: camera,
                isOrthographic: isOrthographic,
                visibleBounds: visibleBounds,
                interfaceColor: interfaceColor
            )
        }
    }
}

extension Geometry {
    func isDescendant(of geometry: Geometry) -> Bool {
        var parent = parent
        while let current = parent {
            if current === geometry {
                return true
            }
            parent = current.parent
        }
        return false
    }
}
