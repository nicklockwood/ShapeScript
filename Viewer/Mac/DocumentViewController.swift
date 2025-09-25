//
//  DocumentViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript

final class DocumentViewController: NSViewController {
    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var scnView: SCNView!

    @IBOutlet private var containerView: NSSplitView!
    @IBOutlet private var errorScrollView: NSScrollView!
    @IBOutlet private(set) var errorTextView: NSTextView!
    @IBOutlet private var loadingIndicator: NSProgressIndicator!
    @IBOutlet private(set) var grantAccessButton: NSButton!
    @IBOutlet private var consoleScrollView: NSScrollView!
    @IBOutlet private var consoleTextView: NSTextView!

    weak var document: Document?

    lazy var cameraNode: SCNNode = makeCameraNode()

    weak var axesNode: SCNNode?

    var errorMessage: NSAttributedString? {
        didSet {
            guard let errorMessage else {
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
        let logLimit = 100000
        let remaining = logLimit - logLength
        if text.isEmpty || remaining <= 0 {
            return
        }
        var text = text
        var truncated = false
        if remaining < text.count {
            truncated = true
            text = text.prefix(remaining) + "... "
        }
        logLength += text.count
        consoleTextView.textStorage?.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.textColor,
                .font: NSFont.systemFont(ofSize: 13),
            ]
        ))
        if truncated {
            consoleTextView.textStorage?.append(NSAttributedString(
                string: "Console limit exceeded. No further logs will be printed.",
                attributes: [
                    .foregroundColor: NSColor.red,
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            ))
        }
        DispatchQueue.main.async {
            self.consoleTextView.scrollToEndOfDocument(self)
        }
    }

    func updateModals() {
        // Does nothing on macOS
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
            if isOrthographic != oldValue {
                refreshOrthographic()
            }
        }
    }

    var camera: Camera = .default {
        didSet {
            if camera != oldValue {
                updateAxesAndCamera()
                resetView()
            }
        }
    }

    var background: MaterialProperty? {
        get { MaterialProperty(scnScene.background) }
        set { newValue?.configureProperty(scnScene.background) }
    }

    var geometry: Geometry? {
        didSet { refreshGeometry() }
    }

    weak var selectedGeometry: Geometry?

    override func viewDidLoad() {
        super.viewDidLoad()

        // create view
        scnView = SCNView(frame: containerView.bounds)
        scnView.autoresizingMask = [.width, .height]
        containerView.insertArrangedSubview(scnView, at: 0)

        // set view background color
        scnView.wantsLayer = true

        // set the scene to the view
        scnView.scene = scnScene

        // configure the view
        scnView.backgroundColor = .clear
        scnView.pointOfView = cameraNode
        refreshGeometry()

        // add a click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        var gestureRecognizers = scnView.gestureRecognizers
        gestureRecognizers.insert(clickGesture, at: 0)
        scnView.gestureRecognizers = gestureRecognizers
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        checkDocumentVersion()
    }

    @discardableResult
    func presentError(_ error: any Error, completionHandler: (() -> Void)? = nil) -> Bool {
        if let window = view.window {
            let alert = NSAlert(error: error)
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window) { _ in
                completionHandler?()
            }
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            return true
        }
        return super.presentError(error)
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        NSAppearance.current = NSApp.effectiveAppearance
        scnView.layer?.backgroundColor = Document.backgroundColor.cgColor
        document?.rerender()
        updateAxesAndCamera()
        if !cameraHasMoved {
            resetView()
        }
    }

    @IBAction func resetCamera(_: Any? = nil) {
        updateAxesAndCamera()
        resetView()
    }

    @IBAction func copyCamera(_: Any? = nil) {
        guard let code = document?.cameraConfig(for: scnView) else {
            NSSound.beep()
            return
        }

        // Copy code to clipboard
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(code, forType: .string)
    }

    @objc func handleClick(_ gestureRecognizer: NSGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        selectGeometry(at: location)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let index = event.characters.flatMap(Int.init)
        {
            if index == 0 {
                resetCamera()
            } else if document?.selectCamera(at: index - 1) == false {
                NSSound.beep()
            }
            return
        }
        switch event.keyCode {
        case 48: // tab
            if event.modifierFlags.contains(.shift) {
                document?.selectPreviousShape()
            } else {
                document?.selectNextShape()
            }
            return
        case 53: // escape
            document?.clearSelection()
            return
        default:
            super.keyDown(with: event)
        }
    }
}

extension DocumentViewController: NSWindowDelegate {
    func windowDidChangeOcclusionState(_: Notification) {
        refreshView()
    }
}
