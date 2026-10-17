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
        let luminance = background?.averageLuminance(over: color) ?? color.luminance
        return luminance > 0.5
    }

    var interfaceColor: OSColor {
        isBrightBackground ? .black : .white
    }

    var visibleBounds: Bounds {
        document?.scene?.visibleBounds ?? .empty
    }

    func checkDocumentWarnings(_ warnings: [String]? = nil) {
        guard !isQuickLook, let document else {
            return
        }
        var messages = warnings ?? document.scene?.warnings ?? []
        if (document.formatVersion ?? ShapeScript.version) > ShapeScript.version {
            let clientVersion = document.clientVersion.map { " (\($0))" } ?? ""
            messages.insert("""
            \(document.fileName) was last edited with a newer version of \
            ShapeScript\(clientVersion) and may not be fully compatible with this version.
            """, at: 0)
        }
        document.warningQueue.update(messages)
        presentQueuedWarning()
    }

    private func presentQueuedWarning() {
        guard !isQuickLook, let document else {
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
                  document.error == nil, errorMessage == nil,
                  document.warningQueue.dismissAll(presentation.id)
            else { return }
            warningPresentation = nil
        })
    }

    func setError(_ error: ProgramError?, message: NSAttributedString?) {
        switch error?.type ?? .evaluation {
        case .evaluation:
            errorTextView.backgroundColor = OSColor(red: 0.8, green: 0, blue: 0, alpha: 0.8)
            grantAccessButton.isHidden = true
        case .fileAccess:
            errorTextView.backgroundColor = OSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
            grantAccessButton.isHidden = isQuickLook
        }
        errorMessage = message
        if error != nil || message != nil {
            warningPresentation = nil
            hideWarning()
        } else {
            presentQueuedWarning()
        }
    }

    func makeCameraNode() -> SCNNode {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 1)
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.usesOrthographicProjection = usesOrthographicProjection
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        return cameraNode
    }

    var usesOrthographicProjection: Bool {
        camera.isOrthographic ?? (isOrthographic && !isQuickLook)
    }

    var cameraHasMoved: Bool {
        scnView.pointOfView != cameraNode
    }

    var axesSize: Double {
        let bounds = visibleBounds
        let m = max(-bounds.min, bounds.max)
        return max(m.x, m.y, m.z) * 1.1
    }

    var viewCenter: Vector {
        showAxes ? .zero : visibleBounds.center
    }

    func resetView() {
        scnView.pointOfView = cameraNode
        scnView.defaultCameraController.worldUp = SCNVector3(camera.upVector)
        scnView.defaultCameraController.target = SCNVector3(viewCenter)
        scnView.antialiasingMode = camera.settings.antialiased ? .multisampling4X : .none
        refreshView()
        didResetView()
    }

    func resetCamera() {
        refreshAxesAndCamera()
        resetView()
    }

    func refreshView() {
        renderTimer?.invalidate()
        scnView.rendersContinuously = true
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scnView.rendersContinuously = false
                self?.renderTimer = nil
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    func refreshScene() {
        defer { didRefreshScene() }
        guard let geometry else {
            selectedGeometry = nil
            scnScene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
            scnView.allowsCameraControl = showAxes
            refreshAxesAndCamera()
            resetView()
            return
        }

        let oldAxesNode = axesNode
        let geometryNodes = scnScene.rootNode.childNodes.filter { $0 !== oldAxesNode }
        if geometryNodes.count == geometry.children.count,
           zip(geometryNodes, geometry.children).allSatisfy({ $1.scnNode === $0 })
        {
            for (node, child) in zip(geometryNodes, geometry.children) {
                node.update(with: child)
            }
        } else {
            geometryNodes.forEach { $0.removeFromParentNode() }
            for child in geometry.children {
                scnScene.rootNode.addChildNode(SCNNode(child))
            }
        }

        // restore selection
        selectGeometry(selectedGeometry?.scnNode)

        // update camera
        refreshAxesAndCamera()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        if !cameraHasMoved {
            resetView()
        } else {
            refreshView()
        }
    }

    func selectGeometry(at location: CGPoint) {
        let focus = geometry?.childIsFocused ?? false
        let geometry = selectableGeometries(at: location).first {
            $0.isSelectableInSelectionMenu(focus: focus)
        }
        selectGeometry(geometry?.scnNode)
    }

    func selectGeometry(_ scnNode: SCNNode?) {
        selectedGeometry = geometry?.select(with: scnNode)
    }

    func selectableGeometries(at location: CGPoint) -> [Geometry] {
        let hits = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        guard let root = geometry else {
            return []
        }
        var geometries = [Geometry]()
        for hit in hits where hit.isVisible {
            guard let geometry = root.geometry(for: hit.node) else {
                continue
            }
            for geometry in geometry.selectionMenuPath(root: root)
                where !geometries.contains(where: { $0 === geometry })
            {
                geometries.append(geometry)
            }
        }
        return geometries
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

    func refreshOrthographic() {
        cameraNode.camera?.usesOrthographicProjection = usesOrthographicProjection
        scnView.pointOfView?.camera?.usesOrthographicProjection = usesOrthographicProjection
        refreshView()
        didRefreshOrthographic()
    }

    func refreshAxes() {
        axesNode?.removeFromParentNode()
        if showAxes, !isQuickLook {
            let axesNode = SCNNode(Axes(
                scale: axesSize,
                camera: camera,
                color: Color(interfaceColor)
            ))
            scnScene.rootNode.insertChildNode(axesNode, at: 0)
            self.axesNode = axesNode
        }
    }

    func refreshCamera() {
        let bounds = visibleBounds
        let axisScale = axesSize * 2.2
        let size = camera.framingSize(bounds.size)
        var distance, scale: Double
        let aspectRatio = Double(scnView.bounds.height / scnView.bounds.width)
        var offset = Vector(0, 0.000001, 0) // Workaround for SceneKit bug
        switch camera.type {
        case .front, .back:
            distance = max(size.x * aspectRatio, size.y) + size.z / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .left, .right:
            distance = max(size.z * aspectRatio, size.y) + size.x / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .top, .bottom:
            distance = max(size.x * aspectRatio, size.z) + size.y / 2
            scale = max(size.x * aspectRatio, size.y * aspectRatio, size.z)
            offset = Vector(0, 0, 0.000001)
        default:
            distance = max(size.x * aspectRatio, size.y) + bounds.size.z / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        }
        if showAxes {
            distance = max(distance, axisScale)
            scale = max(scale, axisScale)
        }
        scale /= 1.8
        let orientation: Rotation
        var position = viewCenter - camera.direction * distance +
            offset.rotated(by: camera.axisRotation)
        if let geometry = camera.geometry {
            orientation = geometry.worldTransform.rotation
            if camera.hasPosition {
                position = geometry.worldTransform.translation
            }
            if camera.hasScale {
                let v = geometry.worldTransform.scale
                scale = max(v.x, v.y, v.z)
            }
        } else {
            orientation = camera.orientation
        }
        cameraNode.camera?.orthographicScale = scale
        cameraNode.position = SCNVector3(position)
        cameraNode.orientation = SCNQuaternion(!camera.hasOrientation && camera.geometry != nil ?
            camera.lookOrientation(towards: viewCenter - position) : orientation)
        scnView.defaultCameraController.worldUp = SCNVector3(camera.upVector)
        cameraNode.camera?.fieldOfView = CGFloat(camera.fov.degrees)
        cameraNode.camera?.usesOrthographicProjection = usesOrthographicProjection
        didRefreshCamera()
    }

    func refreshAxesAndCamera() {
        refreshAxes()
        refreshCamera()
    }
}

extension Geometry {
    func geometry(for scnNode: SCNNode) -> Geometry? {
        if self.scnNode === scnNode {
            return self
        }
        for child in children {
            if let geometry = child.geometry(for: scnNode) {
                return geometry
            }
        }
        return nil
    }

    func select(with scnNode: SCNNode?) -> Geometry? {
        let isSelected = (scnNode != nil && self.scnNode === scnNode)
        if isSelected, self.scnNode?.geometry != nil {
            let g = scnGeometry.copy() as! SCNGeometry
            g.materials = scnGeometry.materials.map {
                let material = $0.copy() as! SCNMaterial
                material.emission.contents = OSColor.red
                material.multiply.contents = OSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1)
                return material
            }
            self.scnNode?.geometry = g
        } else if self.scnNode?.geometry != nil {
            self.scnNode?.geometry = scnGeometry
        }
        var selected = isSelected ? self : nil
        for child in children {
            selected = child.select(with: scnNode) ?? selected
        }
        return selected
    }

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

private extension SCNHitTestResult {
    var isVisible: Bool {
        let material = node.geometry.map { geometry in
            geometry.materials[geometryIndex % geometry.materials.count]
        }
        return material.flatMap { Material($0)?.isVisible } ?? true
    }
}
