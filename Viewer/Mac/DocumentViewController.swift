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

@MainActor
final class DocumentViewController: NSViewController, DocumentViewControllerProtocol {
    static var documentBackgroundColor: Color {
        Document.documentBackgroundColor
    }

    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var scnView: SCNView = .init()

    private var splitView: NSSplitView = .init()
    private var errorScrollView: NSScrollView = .init()
    private(set) var errorTextView: NSTextView = .init()
    private let loadingIndicator: NSProgressIndicator = .init()
    private(set) var grantAccessButton: NSButton = .init()
    private let consoleScrollView: NSScrollView = .init()
    private let consoleTextView: NSTextView = .init()
    private let defaultConsoleHeight: CGFloat = 135

    weak var document: Document?

    var isQuickLook: Bool = false

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
        if logLength > 0 {
            text = "\n\(text)"
        }
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
            if showConsole, !isQuickLook {
                if consoleScrollView.superview == nil {
                    consoleScrollView.frame.size = NSSize(
                        width: splitView.bounds.width,
                        height: defaultConsoleHeight
                    )
                    splitView.insertArrangedSubview(consoleScrollView, at: 1)
                    consoleTextView.textContainerInset = CGSize(width: 5, height: 5)
                }
            } else {
                splitView.removeArrangedSubview(consoleScrollView)
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

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        rootView.autoresizingMask = [.width, .height]

        splitView = NSSplitView(frame: rootView.bounds)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.wantsLayer = true
        rootView.addSubview(splitView)

        errorScrollView = NSScrollView(frame: rootView.bounds)
        errorScrollView.translatesAutoresizingMaskIntoConstraints = false
        errorScrollView.borderType = .noBorder
        errorScrollView.hasHorizontalScroller = false
        errorScrollView.autohidesScrollers = true
        errorScrollView.scrollerKnobStyle = .light
        errorScrollView.isHidden = true
        errorScrollView.wantsLayer = true

        errorTextView = NSTextView(frame: errorScrollView.bounds)
        errorTextView.isEditable = false
        errorTextView.isRichText = false
        errorTextView.importsGraphics = false
        errorTextView.textColor = .white
        errorTextView.backgroundColor = NSColor(
            calibratedRed: 0.863,
            green: 0.129,
            blue: 0.007,
            alpha: 0.8
        )
        errorTextView.autoresizingMask = [.width, .height]
        errorScrollView.documentView = errorTextView
        rootView.addSubview(errorScrollView)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        rootView.addSubview(loadingIndicator)

        grantAccessButton = NSButton(
            title: "Grant Access",
            target: document,
            action: #selector(Document.grantAccess(_:))
        )
        grantAccessButton.attributedTitle = NSAttributedString(
            string: grantAccessButton.title,
            attributes: [.foregroundColor: NSColor.white]
        )
        grantAccessButton.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(grantAccessButton)

        consoleScrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: rootView.bounds.width,
            height: defaultConsoleHeight
        )
        consoleScrollView.hasVerticalScroller = true
        consoleScrollView.hasHorizontalScroller = false
        consoleScrollView.borderType = .noBorder
        consoleTextView.isEditable = false
        consoleTextView.isRichText = false
        consoleTextView.importsGraphics = false
        consoleTextView.backgroundColor = .textBackgroundColor
        consoleScrollView.documentView = consoleTextView

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            errorScrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            errorScrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            errorScrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            errorScrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            loadingIndicator.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            loadingIndicator.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),

            grantAccessButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            grantAccessButton.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // create view
        scnView = SCNView(frame: splitView.bounds)
        scnView.autoresizingMask = [.width, .height]
        splitView.insertArrangedSubview(scnView, at: 0)

        // set view background color
        scnView.wantsLayer = true

        // set the scene to the view
        scnView.scene = scnScene

        // configure the view
        scnView.backgroundColor = .clear
        scnView.pointOfView = cameraNode
        document?.updateViews()
        refreshGeometry()

        // add a click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        scnView.gestureRecognizers.insert(clickGesture, at: 0)
        let contextClickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleContextClick(_:))
        )
        contextClickGesture.buttonMask = 0x2
        scnView.gestureRecognizers.insert(contextClickGesture, at: 0)

        // add click gesture to error view
        let clickGesture2 = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        errorTextView.gestureRecognizers.insert(clickGesture2, at: 0)
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

    @objc func resetCamera(_: Any? = nil) {
        updateAxesAndCamera()
        resetView()
    }

    func resetCamera() {
        resetCamera(nil)
    }

    func copyCamera() {
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

    @objc private func handleContextClick(_ gestureRecognizer: NSGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        guard let menu = selectionContextMenu(at: location) else {
            return
        }
        menu.popUp(positioning: nil, at: location, in: scnView)
    }

    @objc private func selectContextMenuItem(_ menuItem: NSMenuItem) {
        guard let geometry = menuItem.representedObject as? Geometry else {
            return
        }
        selectGeometry(geometry.scnNode)
    }

    private func selectionContextMenu(at location: CGPoint) -> NSMenu? {
        guard let document else {
            return nil
        }

        var geometries = selectableGeometries(at: location)
        if geometries.isEmpty {
            geometries = selectionMenuGeometries(for: document)
        }
        let namesByGeometry = selectionMenuNames(for: document)
        let menu = NSMenu()
        addSelectionMenuItems(
            to: menu,
            for: geometries,
            namesByGeometry: namesByGeometry
        )
        return menu.numberOfItems == 0 ? nil : menu
    }

    @discardableResult
    private func addSelectionMenuItems(
        to menu: NSMenu,
        for geometries: [Geometry],
        namesByGeometry: [ObjectIdentifier: String]
    ) -> Bool {
        var containsSelection = false
        for geometry in geometries where !geometries.contains(where: { geometry.isDescendant(of: $0) }) {
            guard let menuItem = selectionMenuItem(
                for: geometry,
                in: geometries,
                namesByGeometry: namesByGeometry
            ) else {
                continue
            }
            if menuItem.state == .on || menuItem.state == .mixed {
                containsSelection = true
            }
            menu.addItem(menuItem)
        }
        return containsSelection
    }

    private func selectionMenuItem(
        for geometry: Geometry,
        in geometries: [Geometry],
        namesByGeometry: [ObjectIdentifier: String]
    ) -> NSMenuItem? {
        let title = namesByGeometry[ObjectIdentifier(geometry)] ?? document?.geometryName(for: geometry) ?? ""
        let menuItem = NSMenuItem(
            title: title,
            action: geometry.isSelectable ? #selector(selectContextMenuItem(_:)) : nil,
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = geometry
        menuItem.state = (selectedGeometry === geometry) ? .on : .off

        let childGeometries = geometries.filter {
            $0 !== geometry && $0.isDescendant(of: geometry)
        }
        if geometry.hasSelectableChildren, !childGeometries.isEmpty {
            let submenu = NSMenu()
            if addSelectionMenuItems(
                to: submenu,
                for: childGeometries,
                namesByGeometry: namesByGeometry
            ) {
                menuItem.state = .mixed
            }
            menuItem.submenu = submenu
        }

        guard geometry.isSelectable || menuItem.submenu != nil else {
            return nil
        }
        return menuItem
    }

    private func selectionMenuGeometries(for document: Document) -> [Geometry] {
        var geometries = [Geometry]()
        document.enumerateGeometries(in: document.geometry) { geometry in
            geometries.append(geometry)
        }
        return geometries
    }

    private func selectionMenuNames(for document: Document) -> [ObjectIdentifier: String] {
        var countsByType = [String: Int]()
        var namesByGeometry = [ObjectIdentifier: String]()
        document.enumerateGeometries(in: document.geometry) { geometry in
            namesByGeometry[ObjectIdentifier(geometry)] = document.geometryName(
                for: geometry,
                in: &countsByType
            )
        }
        return namesByGeometry
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
