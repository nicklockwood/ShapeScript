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

private final class SelectionSubmenu: NSMenu, @unchecked Sendable {
    let geometry: Geometry
    let namesByGeometry: [ObjectIdentifier: String]

    init(
        title: String,
        geometry: Geometry,
        namesByGeometry: [ObjectIdentifier: String]
    ) {
        self.geometry = geometry
        self.namesByGeometry = namesByGeometry
        super.init(title: title)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class DocumentViewController: NSViewController, DocumentViewControllerProtocol {
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
    private weak var warningView: NSView?
    private var warningDismissHandler: (@MainActor @Sendable () -> Void)?
    private var lastLayoutBackgroundColor: NSColor?

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
        if remaining <= 0 || text.isEmpty && logLength == 0 {
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
                    updateConsoleTextViewSize()
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
        didSet {
            if geometry !== oldValue {
                refreshGeometry()
            }
        }
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
        consoleScrollView.contentView.drawsBackground = false
        consoleTextView.isEditable = false
        consoleTextView.isRichText = false
        consoleTextView.importsGraphics = false
        consoleTextView.isHorizontallyResizable = false
        consoleTextView.isVerticallyResizable = true
        consoleTextView.autoresizingMask = [.width, .height]
        consoleTextView.backgroundColor = .textBackgroundColor
        updateConsoleTextViewSize()
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

    private func updateConsoleTextViewSize() {
        let documentSize = consoleScrollView.bounds.size
        consoleTextView.frame = NSRect(origin: .zero, size: documentSize)
        consoleTextView.minSize = NSSize(width: 0, height: documentSize.height)
        consoleTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        consoleTextView.textContainer?.widthTracksTextView = true
        consoleTextView.textContainer?.heightTracksTextView = false
        consoleTextView.textContainer?.containerSize = NSSize(
            width: documentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
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

    override func viewDidDisappear() {
        super.viewDidDisappear()
        scnView.defaultCameraController.stopInertia()
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

    func showWarning(_ message: String, onDismiss: @escaping @MainActor @Sendable () -> Void) {
        dismissWarning(notify: false)
        warningDismissHandler = onDismiss

        let banner = NSVisualEffectView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.material = .hudWindow
        banner.blendingMode = .withinWindow
        banner.state = .active
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 16
        banner.layer?.cornerCurve = .continuous
        banner.layer?.masksToBounds = true

        let tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.22).cgColor
        banner.addSubview(tintView, positioned: .below, relativeTo: nil)

        let symbol: NSImage? = if #available(macOS 11, *) {
            NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
        } else {
            NSImage(named: NSImage.cautionName)
        }
        let imageView = NSImageView(image: symbol ?? NSImage())
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = .secondaryLabelColor
        if #available(macOS 11, *) {
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 17,
                weight: .semibold
            )
        }

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let closeButton = NSButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(dismissWarningPressed)
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.toolTip = "Dismiss"
        if #available(macOS 11, *) {
            closeButton.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: "Dismiss"
            )
            closeButton.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 15,
                weight: .medium
            )
        } else {
            closeButton.title = "x"
        }
        closeButton.contentTintColor = .secondaryLabelColor

        banner.addSubview(imageView)
        banner.addSubview(label)
        banner.addSubview(closeButton)
        view.addSubview(banner, positioned: .above, relativeTo: nil)
        warningView = banner

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: banner.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: banner.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: banner.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: banner.bottomAnchor),

            banner.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),

            imageView.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -11),

            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func dismissWarningPressed() {
        dismissWarning(notify: true)
    }

    private func dismissWarning(notify: Bool) {
        guard let warningView else {
            if notify, let handler = warningDismissHandler {
                warningDismissHandler = nil
                handler()
            } else if !notify {
                warningDismissHandler = nil
            }
            return
        }
        self.warningView = nil
        guard notify, let handler = warningDismissHandler else {
            warningView.removeFromSuperview()
            if !notify {
                warningDismissHandler = nil
            }
            return
        }
        warningDismissHandler = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            warningView.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                warningView.removeFromSuperview()
                handler()
            }
        }
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        NSAppearance.current = NSApp.effectiveAppearance
        let backgroundColor = backgroundColor
        scnView.layer?.backgroundColor = backgroundColor.cgColor
        if lastLayoutBackgroundColor?.isEqual(backgroundColor) != true {
            lastLayoutBackgroundColor = backgroundColor
            document?.rerender()
        }
        updateAxesAndCamera()
        if !cameraHasMoved {
            resetView()
        }
    }

    @objc func resetCamera(_: Any?) {
        resetCamera()
    }

    func resetCamera() {
        updateAxesAndCamera()
        resetView()
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

        let geometries = selectableGeometries(at: location)
        let namesByGeometry = document.selectionMenuNames()
        let focus = document.geometry.childIsFocused
        let entries = geometries.isEmpty ?
            document.geometry.selectionMenuEntries(focus: focus) :
            Geometry.selectionMenuEntries(for: geometries, focus: focus)
        let menu = NSMenu()
        addSelectionMenuItems(
            to: menu,
            for: entries,
            namesByGeometry: namesByGeometry,
            lazySubmenus: geometries.isEmpty
        )
        return menu.numberOfItems == 0 ? nil : menu
    }

    @discardableResult
    private func addSelectionMenuItems(
        to menu: NSMenu,
        for entries: [SelectionMenuEntry],
        namesByGeometry: [ObjectIdentifier: String],
        lazySubmenus: Bool
    ) -> Bool {
        var containsSelection = false
        for entry in entries {
            let menuItem = selectionMenuItem(
                for: entry,
                namesByGeometry: namesByGeometry,
                lazySubmenus: lazySubmenus
            )
            if menuItem.state == .on || menuItem.state == .mixed {
                containsSelection = true
            }
            menu.addItem(menuItem)
        }
        return containsSelection
    }

    private func selectionMenuItem(
        for entry: SelectionMenuEntry,
        namesByGeometry: [ObjectIdentifier: String],
        lazySubmenus: Bool
    ) -> NSMenuItem {
        let geometry = entry.geometry
        let title = namesByGeometry[ObjectIdentifier(geometry)] ?? document?.geometryName(for: geometry) ?? ""
        let menuItem = NSMenuItem(
            title: title,
            action: entry.isSelectable ? #selector(selectContextMenuItem(_:)) : nil,
            keyEquivalent: ""
        )
        menuItem.target = self
        if entry.isSelectable {
            menuItem.representedObject = geometry
            menuItem.state = (selectedGeometry === geometry) ? .on : .off
        }
        menuItem.isEnabled = true

        if !entry.children.isEmpty {
            if lazySubmenus {
                let submenu = SelectionSubmenu(
                    title: title,
                    geometry: geometry,
                    namesByGeometry: namesByGeometry
                )
                submenu.delegate = self
                submenu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
                menuItem.submenu = submenu
                if selectedGeometry?.isDescendant(of: geometry) == true {
                    menuItem.state = .mixed
                }
            } else {
                let submenu = NSMenu()
                if addSelectionMenuItems(
                    to: submenu,
                    for: entry.children,
                    namesByGeometry: namesByGeometry,
                    lazySubmenus: lazySubmenus
                ) {
                    menuItem.state = .mixed
                }
                menuItem.submenu = submenu
            }
        }

        return menuItem
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

extension DocumentViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menu = menu as? SelectionSubmenu else {
            return
        }
        menu.removeAllItems()
        _ = addSelectionMenuItems(
            to: menu,
            for: menu.geometry.selectionMenuEntries(focus: document?.geometry.childIsFocused ?? false),
            namesByGeometry: menu.namesByGeometry,
            lazySubmenus: true
        )
    }
}

extension DocumentViewController: NSWindowDelegate {
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else {
            return
        }
        guard window.occlusionState.contains(.visible) else {
            scnView.defaultCameraController.stopInertia()
            return
        }
        refreshView()
    }

    func windowDidResignKey(_: Notification) {
        scnView.defaultCameraController.stopInertia()
    }
}
