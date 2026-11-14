//
//  SceneKitRenderer.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 06/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript

protocol SceneRenderer: AnyObject, Sendable {
    var supportsIncrementalGeometryUpdates: Bool { get }
    func validate(_ scene: Scene, source: String) throws
    func prepare(_ scene: Scene, options: Scene.OutputOptions)
    func prepareAsync(_ scene: Scene, options: Scene.OutputOptions) async
}

extension SceneRenderer {
    var supportsIncrementalGeometryUpdates: Bool { true }

    func prepareAsync(_ scene: Scene, options: Scene.OutputOptions) async {
        prepare(scene, options: options)
    }
}

@MainActor
final class SceneKitRenderer: @unchecked Sendable {
    let scene = SCNScene()
    let view: SCNView

    init(view: SCNView = SCNView()) {
        self.view = view
    }

    var renderTimer: Timer?
    lazy var cameraNode: SCNNode = makeCameraNode()
    weak var axesNode: SCNNode?

    var background: MaterialProperty? {
        get { MaterialProperty(scene.background) }
        set { newValue?.configureProperty(scene.background) }
    }

    var cameraHasMoved: Bool {
        view.pointOfView != cameraNode
    }

    func makeCameraNode() -> SCNNode {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 1)
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        return cameraNode
    }

    func resetView(
        target: Vector,
        cameraUp: Vector,
        isAntialiased: Bool
    ) {
        view.pointOfView = cameraNode
        view.defaultCameraController.worldUp = SCNVector3(cameraUp)
        view.defaultCameraController.target = SCNVector3(target)
        view.antialiasingMode = isAntialiased ? .multisampling4X : .none
        refreshView()
    }

    func refreshView() {
        renderTimer?.invalidate()
        view.rendersContinuously = true
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.view.rendersContinuously = false
                self?.renderTimer = nil
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    func refreshGeometry(
        _ geometry: Geometry?,
        selectedGeometry: Geometry?,
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        isOrthographic: Bool,
        visibleBounds: Bounds,
        interfaceColor: OSColor
    ) {
        guard let geometry else {
            scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
            view.allowsCameraControl = showAxes
            updateAxesAndCamera(
                showAxes: showAxes,
                isQuickLook: isQuickLook,
                camera: camera,
                isOrthographic: isOrthographic,
                visibleBounds: visibleBounds,
                interfaceColor: interfaceColor
            )
            resetView(
                target: viewCenter(showAxes: showAxes, visibleBounds: visibleBounds),
                cameraUp: camera.upVector,
                isAntialiased: camera.settings.antialiased
            )
            return
        }

        let oldAxesNode = axesNode
        let geometryNodes = scene.rootNode.childNodes.filter { $0 !== oldAxesNode }
        if geometryNodes.count == geometry.children.count,
           zip(geometryNodes, geometry.children).allSatisfy({ $1.scnNode === $0 })
        {
            for (node, child) in zip(geometryNodes, geometry.children) {
                node.update(with: child)
            }
        } else {
            geometryNodes.forEach { $0.removeFromParentNode() }
            for child in geometry.children {
                scene.rootNode.addChildNode(SCNNode(child))
            }
        }

        _ = selectGeometry(selectedGeometry?.scnNode, in: geometry)
        updateAxesAndCamera(
            showAxes: showAxes,
            isQuickLook: isQuickLook,
            camera: camera,
            isOrthographic: isOrthographic,
            visibleBounds: visibleBounds,
            interfaceColor: interfaceColor
        )
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        if !cameraHasMoved {
            resetView(
                target: viewCenter(showAxes: showAxes, visibleBounds: visibleBounds),
                cameraUp: camera.upVector,
                isAntialiased: camera.settings.antialiased
            )
        } else {
            refreshView()
        }
    }

    func selectGeometry(at location: CGPoint, in root: Geometry) -> Geometry? {
        let focus = root.childIsFocused
        let geometry = selectableGeometries(at: location, in: root).first {
            $0.type != .group && $0.isSelectableInSelectionMenu(focus: focus)
        }
        return selectGeometry(geometry?.scnNode, in: root)
    }

    func selectGeometry(_ scnNode: SCNNode?, in root: Geometry?) -> Geometry? {
        root?.select(with: scnNode)
    }

    func selectableGeometries(at location: CGPoint, in root: Geometry) -> [Geometry] {
        let hits = view.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        var geometries = [Geometry]()
        for hit in hits where hit.isVisible {
            guard let geometry = root.geometry(for: hit.node) else {
                continue
            }
            for geometry in geometry.selectionMenuPath(root: root) {
                if !geometries.contains(where: { $0 === geometry }) {
                    geometries.append(geometry)
                }
            }
        }
        return geometries
    }

    func resetCamera(
        camera: Camera,
        visibleBounds: Bounds,
        showAxes: Bool
    ) {
        resetView(
            target: viewCenter(showAxes: showAxes, visibleBounds: visibleBounds),
            cameraUp: camera.upVector,
            isAntialiased: camera.settings.antialiased
        )
        view.defaultCameraController.worldUp = SCNVector3(camera.upVector)
    }

    func refreshOrthographic(
        camera: Camera,
        isOrthographic: Bool,
        isQuickLook: Bool
    ) {
        let ortho = camera.isOrthographic ?? (isOrthographic && !isQuickLook)
        cameraNode.camera?.usesOrthographicProjection = ortho
        view.pointOfView?.camera?.usesOrthographicProjection = ortho
        refreshView()
    }

    func updateAxesAndCamera(
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        isOrthographic: Bool,
        visibleBounds: Bounds,
        interfaceColor: OSColor
    ) {
        updateAxes(
            showAxes: showAxes,
            isQuickLook: isQuickLook,
            camera: camera,
            visibleBounds: visibleBounds,
            interfaceColor: interfaceColor
        )
        updateCamera(
            showAxes: showAxes,
            isQuickLook: isQuickLook,
            camera: camera,
            isOrthographic: isOrthographic,
            visibleBounds: visibleBounds
        )
    }

    private func updateAxes(
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        visibleBounds: Bounds,
        interfaceColor: OSColor
    ) {
        axesNode?.removeFromParentNode()
        if showAxes, !isQuickLook {
            let axesNode = SCNNode(Axes(
                scale: axesSize(for: visibleBounds),
                camera: camera,
                color: Color(interfaceColor)
            ))
            scene.rootNode.insertChildNode(axesNode, at: 0)
            self.axesNode = axesNode
        }
    }

    private func updateCamera(
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        isOrthographic: Bool,
        visibleBounds: Bounds
    ) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let framing = camera.framing(
            visibleBounds: visibleBounds,
            viewSize: view.bounds.size,
            showAxes: showAxes
        )
        cameraNode.camera?.orthographicScale = framing.orthographicScale
        cameraNode.position = SCNVector3(framing.transform.translation)
        cameraNode.orientation = SCNQuaternion(framing.transform.rotation)
        view.defaultCameraController.worldUp = SCNVector3(camera.upVector)
        cameraNode.camera?.fieldOfView = CGFloat(camera.fov.degrees)
        cameraNode.camera?.usesOrthographicProjection = camera.isOrthographic ?? (isOrthographic && !isQuickLook)
    }

    private func axesSize(for visibleBounds: Bounds) -> Double {
        let m = max(-visibleBounds.min, visibleBounds.max)
        return max(m.x, m.y, m.z) * 1.1
    }

    private func viewCenter(showAxes: Bool, visibleBounds: Bounds) -> Vector {
        showAxes ? .zero : visibleBounds.center
    }
}

extension SceneKitRenderer: SceneRenderer {
    nonisolated func validate(_ scene: Scene, source: String) throws {
        try Self.validate(scene, source: source)
    }

    nonisolated func prepare(_ scene: Scene, options: Scene.OutputOptions) {
        scene.scnBuild(with: options)
    }

    private nonisolated static func validate(_ scene: Scene, source: String) throws {
        let maxLights = 8
        let nonAmbientLights = scene.lights.filter {
            $0.light.map { SCNLight($0).type != .ambient } ?? false
        }
        if nonAmbientLights.count > maxLights {
            throw RuntimeError(
                .assertionFailure("""
                There is a maximum of \(maxLights) non-ambient lights per scene. \
                This scene has \(nonAmbientLights.count) lights
                """),
                at: nonAmbientLights[maxLights].sourceLocation?
                    .range(in: source) ?? source.startIndex ..< source.startIndex
            )
        }
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
        select(with: scnNode, ancestorIsSelected: false)
    }

    private func select(with scnNode: SCNNode?, ancestorIsSelected: Bool) -> Geometry? {
        let isSelected = (scnNode != nil && self.scnNode === scnNode)
        let highlight = isSelected || ancestorIsSelected
        if highlight, self.scnNode?.geometry != nil {
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
            selected = child.select(with: scnNode, ancestorIsSelected: highlight) ?? selected
        }
        return selected
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
