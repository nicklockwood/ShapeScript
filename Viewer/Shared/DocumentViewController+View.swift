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
    }

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
        scnView.antialiasingMode = (camera.settings?.antialiased ?? true) ? .multisampling4X : .none
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

        guard let geometry = geometry else {
            scnView.allowsCameraControl = showAxes
            updateAxesAndCamera()
            resetView()
            return
        }

        // create geometry
        for child in geometry.children {
            scnScene.rootNode.addChildNode(SCNNode(child))
        }

        // restore selection
        selectGeometry(selectedGeometry?.scnNode)

        // update camera
        updateAxesAndCamera()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        if !cameraHasMoved {
            resetView()
        } else {
            refreshView()
        }
    }

    func selectGeometry(_ scnNode: SCNNode?) {
        selectedGeometry = geometry?.select(with: scnNode)
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
        let bounds = geometry?.bounds ?? .empty
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
    func select(with scnNode: SCNNode?) -> Geometry? {
        let isSelected = (scnNode != nil && self.scnNode === scnNode)
        if isSelected {
            let g = scnGeometry.copy() as! SCNGeometry
            g.materials = scnGeometry.materials.map {
                let material = $0.copy() as! SCNMaterial
                material.emission.contents = OSColor.red
                material.multiply.contents = OSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1)
                return material
            }
            self.scnNode?.geometry = g
        } else {
            self.scnNode?.geometry = scnGeometry
        }
        var selected = isSelected ? self : nil
        for child in children {
            let g = child.select(with: scnNode)
            selected = selected ?? g
        }
        return selected
    }
}
