//
//  SceneViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import QuartzCore
import SceneKit
import ShapeScript

class SceneViewController: NSViewController {
    let scnScene = SCNScene()
    private(set) var scnView: SCNView!
    private var renderTimer: Timer?

    @IBOutlet private var containerView: NSSplitView!
    @IBOutlet private var errorScrollView: NSScrollView!
    @IBOutlet private var errorTextView: NSTextView!
    @IBOutlet private var loadingIndicator: NSProgressIndicator!
    @IBOutlet private var grantAccessButton: NSButton!
    @IBOutlet private var consoleScrollView: NSScrollView!
    @IBOutlet private var consoleTextView: NSTextView!

    lazy var cameraNode: SCNNode = {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 1)
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.usesOrthographicProjection = camera.isOrthographic ?? isOrthographic
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        return cameraNode
    }()

    lazy var axesNode: SCNNode = .init(Axes(
        scale: axesSize,
        camera: camera,
        background: background
    ))

    var errorMessage: NSAttributedString? {
        didSet {
            guard let errorMessage = errorMessage else {
                errorScrollView.isHidden = true
                return
            }
            errorTextView.textContainerInset = CGSize(width: 20, height: 20)
            errorTextView.textStorage?.setAttributedString(errorMessage)
            errorScrollView.isHidden = false
        }
    }

    private var logLength: Int = 0

    func clearLog() {
        logLength = 0
        consoleTextView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    func appendLog(_ text: String) {
        if text.isEmpty {
            return
        }
        let logLimit = 20000
        let charCount = text.count
        logLength += charCount
        if logLength > logLimit {
            if logLength - charCount > logLimit {
                return
            }
            consoleTextView.textStorage?.append(NSAttributedString(
                string: "Console limit exceeded. No further logs will be printed.",
                attributes: [
                    .foregroundColor: NSColor.red,
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            ))
        } else {
            consoleTextView.textStorage?.append(NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: NSColor.textColor,
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            ))
        }
        DispatchQueue.main.async {
            self.consoleTextView.scrollToEndOfDocument(self)
        }
    }

    var showAccessButton = false {
        didSet {
            guard showAccessButton != oldValue else {
                return
            }
            grantAccessButton.isHidden = !showAccessButton
            errorTextView.backgroundColor = showAccessButton ?
                NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) :
                NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        }
    }

    var isLoading = false {
        didSet {
            guard isLoading != oldValue else {
                return
            }
            if isLoading {
                loadingIndicator.startAnimation(nil)
            } else {
                loadingIndicator.stopAnimation(nil)
                refreshView()
            }
        }
    }

    var showConsole = false {
        didSet {
            guard showConsole != oldValue else {
                return
            }
            if showConsole {
                if consoleScrollView.superview == nil {
                    containerView.insertArrangedSubview(consoleScrollView, at: 1)
                    consoleTextView.textContainerInset = CGSize(width: 5, height: 5)
                }
            } else {
                containerView.removeArrangedSubview(consoleScrollView)
            }
        }
    }

    var showAxes = false {
        didSet {
            if showAxes != oldValue {
                updateAxesAndCamera()
            }
        }
    }

    var isOrthographic = false {
        didSet {
            guard isOrthographic != oldValue else {
                return
            }
            cameraNode.camera?.usesOrthographicProjection =
                camera.isOrthographic ?? isOrthographic
            resetCamera(nil)
        }
    }

    var camera: Camera = .default {
        didSet {
            if camera != oldValue {
                updateAxesAndCamera()
            }
        }
    }

    var background: MaterialProperty? {
        get { MaterialProperty(scnMaterialProperty: scnScene.background) }
        set { newValue?.configureProperty(scnScene.background) }
    }

    private var lastBoundsSet: Bounds?

    var geometry: Geometry? {
        didSet {
            refreshGeometry()
            if geometry?.isEmpty == false, geometry?.bounds != lastBoundsSet {
                lastBoundsSet = geometry?.bounds
                updateAxesAndCamera()
            }
            refreshView()
        }
    }

    private func refreshGeometry() {
        // clear scene
        scnScene.rootNode.childNodes.forEach { $0.removeFromParentNode() }

        // add axes
        if showAxes {
            scnScene.rootNode.addChildNode(axesNode)
        }

        // restore selection
        selectGeometry(selectedGeometry?.scnGeometry)

        guard let geometry = geometry, !geometry.bounds.isEmpty else {
            scnView.allowsCameraControl = showAxes
            return
        }

        // create geometry
        geometry.children.forEach {
            scnScene.rootNode.addChildNode(SCNNode($0))
        }

        // update camera
        scnView.allowsCameraControl = true
    }

    private func refreshView() {
        renderTimer?.invalidate()
        scnView.rendersContinuously = true
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            self.scnView.rendersContinuously = false
            self.renderTimer = nil
        }
    }

    private var viewCenter: Vector {
        showAxes ? .zero : (geometry?.bounds ?? .empty).center
    }

    private var axesSize: Double {
        let bounds = geometry?.bounds ?? .empty
        let m = max(-bounds.min, bounds.max)
        return max(m.x, m.y, m.z) * 1.1
    }

    private(set) weak var selectedGeometry: Geometry?
    func selectGeometry(_ scnGeometry: SCNGeometry?) {
        selectedGeometry = geometry?.select(with: scnGeometry)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        var options: [String: Any]?
        if useOpenGL {
            options = [
                SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.openGLLegacy.rawValue,
            ]
        }

        // create view
        scnView = SCNView(frame: containerView.bounds, options: options)
        scnView.autoresizingMask = [.width, .height]
        containerView.insertArrangedSubview(scnView, at: 0)

        // set view background color
        scnView.wantsLayer = true
        scnView.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        // set the scene to the view
        scnView.scene = scnScene

        // configure the view
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling16X
        scnView.allowsCameraControl = geometry != nil
        updateAxesAndCamera()

        // add a click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        var gestureRecognizers = scnView.gestureRecognizers
        gestureRecognizers.insert(clickGesture, at: 0)
        scnView.gestureRecognizers = gestureRecognizers
    }

    private func updateAxesAndCamera() {
        // Update axes
        axesNode.removeFromParentNode()
        axesNode = SCNNode(Axes(
            scale: axesSize,
            camera: camera,
            background: background
        ))
        if showAxes {
            scnScene.rootNode.insertChildNode(axesNode, at: 0)
        }
        // Update camera node
        guard let bounds = geometry?.bounds else {
            return
        }
        let axisScale = axesSize * 2.2
        let size = bounds.size
        var distance, scale: Double
        var offset = Vector(0, 0.000001, 0) // Workaround for SceneKit bug
        switch camera.type {
        case .front, .back:
            distance = max(size.x * 0.75, size.y) + bounds.size.z / 2
            scale = max(size.x * 0.75, size.y, size.z * 0.75)
        case .left, .right:
            distance = max(size.z * 0.75, size.y) + bounds.size.x / 2
            scale = max(size.x * 0.75, size.y, size.z * 0.75)
        case .top, .bottom:
            distance = max(size.x * 0.75, size.z) + bounds.size.y / 2
            scale = max(size.x * 0.75, size.y * 0.75, size.z)
            offset = Vector(0, 0, 0.000001)
        default:
            distance = max(size.x * 0.75, size.y) + bounds.size.z / 2
            scale = max(size.x * 0.75, size.y, size.z * 0.75)
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
                scale = max(v.x, v.y, v.z) / 2
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
        resetCamera(nil)
    }

    @IBAction func resetCamera(_: Any?) {
        scnView.defaultCameraController.target = SCNVector3(viewCenter)
        scnView.pointOfView = cameraNode
        refreshView()
    }

    @objc func handleClick(_ gestureRecognizer: NSGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [:])
        selectGeometry(hitResults.first?.node.geometry)
    }
}

extension SceneViewController: NSWindowDelegate {
    func windowDidChangeOcclusionState(_: Notification) {
        refreshView()
    }
}

private extension Geometry {
    func select(with scnGeometry: SCNGeometry?) -> Geometry? {
        let isSelected = (self.scnGeometry == scnGeometry)
        for material in self.scnGeometry.materials {
            material.emission.contents = isSelected ? NSColor.red : .black
            material.multiply.contents = isSelected ? NSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1) : .white
        }
        var selected = isSelected ? self : nil
        for child in children {
            let g = child.select(with: scnGeometry)
            selected = selected ?? g
        }
        return selected
    }
}
