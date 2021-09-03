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
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        return cameraNode
    }()

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

    func clearLog() {
        consoleTextView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    func appendLog(_ text: NSAttributedString) {
        if text.string.isEmpty {
            return
        }
        consoleTextView.textStorage?.append(text)
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

    public var showConsole = false {
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

    public var showAxes = false {
        didSet {
            guard showAxes != oldValue else {
                return
            }
            let geometry = self.geometry
            self.geometry = geometry
            resetCamera(nil)
        }
    }

    var background: MaterialProperty? {
        get { MaterialProperty(scnMaterialProperty: scnScene.background) }
        set { newValue?.configureProperty(scnScene.background) }
    }

    var geometry: Geometry? {
        didSet {
            // clear scene
            scnScene.rootNode.childNodes.forEach { $0.removeFromParentNode() }

            // add axes
            let bounds = viewBounds
            let size = bounds.size
            let scale = max(size.x, size.y, size.z, 1)
            if showAxes {
                let axes = Axes(scale: scale / 2, background: background)
                scnScene.rootNode.addChildNode(SCNNode(axes))
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
            let center = bounds.center
            let distance = scale * 1.2 + cameraNode.camera!.zNear
            cameraNode.position = SCNVector3(center.x, center.y, distance)
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.target = SCNVector3(center)
            refreshView()
        }
    }

    private func refreshView() {
        scnView.rendersContinuously = true
        scnView.rendersContinuously = false
    }

    private var viewBounds: Bounds {
        let bounds = geometry?.bounds ?? .empty
        guard showAxes else {
            return bounds
        }
        let m = max(-bounds.min, bounds.max) + Vector(size: [0.1])
        return Bounds(min: -m, max: m)
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
        resetCamera(nil)

        // add a click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        var gestureRecognizers = scnView.gestureRecognizers
        gestureRecognizers.insert(clickGesture, at: 0)
        scnView.gestureRecognizers = gestureRecognizers
    }

    @IBAction func resetCamera(_: Any?) {
        scnView.defaultCameraController.target = SCNVector3(viewBounds.center)
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
