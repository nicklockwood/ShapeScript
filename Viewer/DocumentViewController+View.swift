//
//  DocumentViewController+View.swift
//  ShapeScriptApp
//
//  Created by Nick Lockwood on 09/09/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript

extension DocumentViewController {
    func makeCameraNode() -> SCNNode {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 1)
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.usesOrthographicProjection = camera.isOrthographic ?? isOrthographic
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        return cameraNode
    }

    var cameraHasMoved: Bool {
        scnView.pointOfView != cameraNode
    }

    var axesSize: Double {
        let bounds = geometry?.bounds ?? .empty
        let m = max(-bounds.min, bounds.max)
        return max(m.x, m.y, m.z) * 1.1
    }

    var viewCenter: Vector {
        showAxes ? .zero : (geometry?.bounds ?? .empty).center
    }

    func resetView() {
        scnView.defaultCameraController.target = SCNVector3(viewCenter)
        scnView.pointOfView = cameraNode
        refreshView()
    }

    func refreshView() {
        renderTimer?.invalidate()
        scnView.rendersContinuously = true
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            self.scnView.rendersContinuously = false
            self.renderTimer = nil
        }
    }

    func refreshGeometry() {
        // clear scene
        scnScene.rootNode.childNodes.forEach { $0.removeFromParentNode() }

        // update axes
        updateAxesAndCamera()

        // restore selection
        selectGeometry(selectedGeometry?.scnGeometry)

        guard let geometry = geometry, !geometry.bounds.isEmpty else {
            scnView.allowsCameraControl = showAxes
            refreshView()
            return
        }

        // create geometry
        geometry.children.forEach {
            scnScene.rootNode.addChildNode(SCNNode($0))
        }

        // update camera
        updateAxesAndCamera()
        scnView.allowsCameraControl = true
        if !cameraHasMoved {
            resetView()
        } else {
            refreshView()
        }
    }

    func selectGeometry(_ scnGeometry: SCNGeometry?) {
        selectedGeometry = geometry?.select(with: scnGeometry)
    }

    func refreshOrthographic() {
        let ortho = camera.isOrthographic ?? isOrthographic
        cameraNode.camera?.usesOrthographicProjection = ortho
        scnView.pointOfView?.camera?.usesOrthographicProjection = ortho
        refreshView()
    }

    func updateAxesAndCamera() {
        // Update axes
        axesNode?.removeFromParentNode()
        if showAxes {
            let axesNode = SCNNode(Axes(
                scale: axesSize,
                camera: camera,
                background: background,
                backgroundColor: Color(Document.backgroundColor)
            ))
            scnScene.rootNode.insertChildNode(axesNode, at: 0)
            self.axesNode = axesNode
        }
        // Update camera node
        guard let bounds = geometry?.bounds else {
            return
        }
        let axisScale = axesSize * 2.2
        let size = bounds.size
        var distance, scale: Double
        let aspectRatio = Double(view.bounds.height / view.bounds.width)
        var offset = Vector(0, 0.000001, 0) // Workaround for SceneKit bug
        switch camera.type {
        case .front, .back:
            distance = max(size.x * aspectRatio, size.y) + bounds.size.z / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .left, .right:
            distance = max(size.z * aspectRatio, size.y) + bounds.size.x / 2
            scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        case .top, .bottom:
            distance = max(size.x * aspectRatio, size.z) + bounds.size.y / 2
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
        var position = viewCenter - camera.direction * distance + offset
        if let geometry = camera.geometry {
            orientation = geometry.worldTransform.rotation
            if camera.hasPosition {
                position = geometry.worldTransform.offset
            }
            if camera.hasScale {
                let v = geometry.worldTransform.scale
                scale = max(v.x, v.y, v.z)
            }
        } else {
            orientation = .identity
        }
        cameraNode.camera?.orthographicScale = scale
        cameraNode.position = SCNVector3(position)
        cameraNode.orientation = SCNQuaternion(orientation)
        if !camera.hasOrientation {
            cameraNode.look(at: SCNVector3(viewCenter))
        }
        cameraNode.camera?.fieldOfView = CGFloat(camera.fov?.degrees ?? 60)
        cameraNode.camera?.usesOrthographicProjection = camera.isOrthographic ?? isOrthographic
    }
}

extension Geometry {
    func select(with scnGeometry: SCNGeometry?) -> Geometry? {
        let isSelected = (self.scnGeometry == scnGeometry)
        for material in self.scnGeometry.materials {
            material.emission.contents = isSelected ? OSColor.red : .black
            material.multiply.contents = isSelected ? OSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1) : .white
        }
        var selected = isSelected ? self : nil
        for child in children {
            let g = child.select(with: scnGeometry)
            selected = selected ?? g
        }
        return selected
    }
}
