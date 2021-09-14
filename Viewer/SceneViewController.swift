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
            if showAxes {
                let axes = Axes(scale: size.x / 2, background: background)
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
            let distance = showAxes ? size.z * 1.1 : max(size.x * 0.75, size.y) + bounds.max.z
            cameraNode.position = SCNVector3(center.x, center.y, center.z + distance)
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
        var m = max(-bounds.min, bounds.max) * 1.1
        m = Vector(size: [max(m.x, m.y, m.z)])
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
