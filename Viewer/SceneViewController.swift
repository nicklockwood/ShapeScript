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
    private var scnView: SCNView!

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
            grantAccessButton.isHidden = !showAccessButton
            errorTextView.backgroundColor = showAccessButton ?
                NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) :
                NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        }
    }

    var isLoading = false {
        didSet {
            if isLoading {
                loadingIndicator.startAnimation(nil)
            } else {
                loadingIndicator.stopAnimation(nil)
            }
        }
    }

    public var showWireframe = false {
        didSet {
            guard scnView.renderingAPI == .metal else {
                return
            }
            if showWireframe {
                scnView.debugOptions.insert(.showWireframe)
            } else {
                scnView.debugOptions.remove(.showWireframe)
            }
        }
    }

    public var showConsole = false {
        didSet {
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

    var background: MaterialProperty? {
        get { MaterialProperty(scnMaterialProperty: scnScene.background) }
        set { newValue?.configureProperty(scnScene.background) }
    }

    var geometry: Geometry? {
        didSet {
            // clear scene
            scnScene.rootNode.childNodes.forEach { $0.removeFromParentNode() }

            // restore selection
            selectGeometry(selectedGeometry?.scnGeometry)

            guard let geometry = geometry, !geometry.bounds.isEmpty else {
                scnView.allowsCameraControl = false
                return
            }

            // create geometry
            geometry.children.forEach {
                scnScene.rootNode.addChildNode(SCNNode($0))
            }

            // update camera
            let bounds = geometry.bounds
            let center = bounds.center
            let distance = max(bounds.size.x, bounds.size.y) + bounds.max.z + cameraNode.camera!.zNear
            cameraNode.position = SCNVector3(center.x, center.y, distance + cameraNode.camera!.zNear)
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.target = SCNVector3(center)
        }
    }

    private(set) weak var selectedGeometry: Geometry?
    private func selectGeometry(_ scnGeometry: SCNGeometry?) {
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
        scnView.allowsCameraControl = geometry != nil
        resetCamera(nil)

        // add a click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        var gestureRecognizers = scnView.gestureRecognizers
        gestureRecognizers.insert(clickGesture, at: 0)
        scnView.gestureRecognizers = gestureRecognizers
    }

    @IBAction func resetCamera(_: Any?) {
        let center = geometry?.bounds.center ?? Vector.zero
        scnView.defaultCameraController.target = SCNVector3(center)
        scnView.pointOfView = cameraNode

        // trigger an update
        scnView.rendersContinuously = true
        scnView.rendersContinuously = false
    }

    @objc func handleClick(_ gestureRecognizer: NSGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [:])
        selectGeometry(hitResults.first?.node.geometry)
    }
}
