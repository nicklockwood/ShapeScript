//
//  Document.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa
import SceneKit
import ShapeScript

class Document: NSDocument {
    static var backgroundColor: NSColor {
        if Thread.isMainThread {
            NSAppearance.current = NSApp.effectiveAppearance
        } else {
            DispatchQueue.main.sync {
                NSAppearance.current = NSApp.effectiveAppearance
            }
        }
        return .underPageBackgroundColor
    }

    let cache = GeometryCache()
    let settings = Settings.shared
    private(set) var fileMonitor: FileMonitor?

    var viewController: DocumentViewController? {
        let viewController = windowControllers.compactMap {
            $0.window?.contentViewController as? DocumentViewController
        }.first
        viewController?.document = self
        return viewController
    }

    var scene: Scene? {
        didSet {
            updateCameras()
            updateViews()
        }
    }

    var geometry: Geometry {
        Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: scene?.children ?? [],
            sourceLocation: nil
        )
    }

    var loadingProgress: LoadingProgress? {
        didSet { updateViews() }
    }

    var errorMessage: NSAttributedString?
    var error: ProgramError?
    var rerenderRequired: Bool = false
    private var observer: Any?

    var sourceString: String? {
        didSet { didUpdateSource() }
    }

    override var fileURL: URL? {
        didSet {
            fileMonitor = FileMonitor(fileURL) { [weak self] url in
                _ = try self?.read(from: url, ofType: url.pathExtension)
            }
        }
    }

    override func makeWindowControllers() {
        dismissOpenSavePanel()

        if fileURL == nil {
            showNewDocumentPanel()
            return
        }

        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard
            .instantiateController(withIdentifier: NSStoryboard
                .SceneIdentifier("Document Window Controller")) as! NSWindowController
        addWindowController(windowController)
        guard let newWindow = windowController.window else {
            return
        }
        newWindow.delegate = windowController.contentViewController as? NSWindowDelegate
        if let currentWindow = NSDocumentController.shared.currentDocument?
            .windowControllers.first?.window, currentWindow.tabbedWindows != nil
        {
            currentWindow.addTabbedWindow(newWindow, ordered: .above)
        }
        updateViews()

        // Observe settings changes.
        observer = NotificationCenter.default.addObserver(
            forName: .settingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rerender()
            self?.updateViews()
        }
    }

    override func close() {
        super.close()
        observer.map(NotificationCenter.default.removeObserver)
        loadingProgress?.cancel()
        fileMonitor = nil
    }

    override func read(from url: URL, ofType _: String) throws {
        try load(Data(contentsOf: url), fileURL: url)
    }

    @IBAction private func didSelectEditor(_ sender: NSPopUpButton) {
        handleEditorPopupAction(for: sender, in: windowForSheet)
    }

    private func openFileInEditor(_ fileURL: URL?) {
        guard let fileURL = fileURL else {
            return
        }
        guard settings.userDidChooseEditor, let editor = settings.selectedEditor else {
            let popup = NSPopUpButton(title: "", target: self, action: #selector(didSelectEditor))
            configureEditorPopup(popup)
            popup.sizeToFit()

            let actionSheet = NSAlert()
            actionSheet.messageText = "Open in External Editor"
            actionSheet.informativeText = """
            ShapeScript does not include a built-in editor. Choose an external editor to use from the menu below.

            You can choose a different editor later from ShapeScript > Preferences…
            """
            actionSheet.accessoryView = popup
            actionSheet.addButton(withTitle: "Open")
            actionSheet.addButton(withTitle: "Cancel")
            showSheet(actionSheet, in: windowForSheet) { response in
                switch response {
                case .alertFirstButtonReturn:
                    self.settings.userDidChooseEditor = true
                    self.didSelectEditor(popup)
                    self.openFileInEditor(fileURL)
                default:
                    break
                }
            }
            return
        }

        do {
            try NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: editor.url,
                options: [],
                configuration: [:]
            )
        } catch {
            settings.userDidChooseEditor = false
            presentError(error)
        }
    }

    @IBAction func openInEditor(_: AnyObject) {
        openFileInEditor(errorURL ?? selectedGeometry?.sourceLocation?.file ?? fileURL)
    }

    @IBAction func grantAccess(_: Any?) {
        let dialog = NSOpenPanel()
        dialog.title = "Grant Access"
        dialog.showsHiddenFiles = false
        dialog.directoryURL = error?.accessErrorURL
        dialog.canChooseDirectories = true
        showSheet(dialog, in: windowForSheet) { response in
            guard response == .OK, let fileURL = self.fileURL, let url = dialog.url else {
                return
            }
            self.bookmarkURL(url)
            do {
                _ = try self.read(from: fileURL, ofType: fileURL.pathExtension)
            } catch {}
        }
    }

    @IBAction func revealInFinder(_: AnyObject) {
        if let fileURL = fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    @IBAction func showModelInfo(_: AnyObject) {
        let actionSheet = NSAlert()
        actionSheet.messageText = selectedGeometry.map { _ in
            "Selected Shape Info"
        } ?? "Scene Info"
        actionSheet.informativeText = modelInfo
        actionSheet.addButton(withTitle: "OK")
        actionSheet.addButton(withTitle: "Open in Editor")
        let fileURL = selectedGeometry?.sourceLocation?.file ?? self.fileURL
        showSheet(actionSheet, in: windowForSheet) { [weak self] response in
            switch response {
            case .alertSecondButtonReturn:
                self?.openFileInEditor(fileURL)
            default:
                break
            }
        }
    }

    // MARK: Selection

    private var selectMenu: NSMenu?

    private func configureSelectMenu(
        _ menu: NSMenu,
        for shape: Geometry,
        with index: inout Int,
        countsByType: inout [String: Int]
    ) -> Bool {
        menu.removeAllItems()
        var containsSelection = false
        for shape in shape.children {
            let isSelectable = shape.isSelectable
            let hasSelectableChildren = shape.hasSelectableChildren
            guard isSelectable || hasSelectableChildren else {
                continue
            }
            let menuItem = menu.addItem(
                withTitle: geometryName(for: shape, in: &countsByType),
                action: #selector(selectShape(_:)),
                keyEquivalent: ""
            )
            if isSelectable {
                index += 1
                menuItem.tag = index
                menuItem.state = (selectedGeometry === shape) ? .on : .off
                if !containsSelection {
                    containsSelection = (selectedGeometry === shape)
                }
            }
            if hasSelectableChildren {
                let submenu = NSMenu()
                if configureSelectMenu(
                    submenu,
                    for: shape,
                    with: &index,
                    countsByType: &countsByType
                ) {
                    containsSelection = true
                    menuItem.state = .mixed
                }
                menuItem.submenu = submenu
            }
        }
        return containsSelection
    }

    private func enumerateGeometries(
        in shape: Geometry,
        with fn: (Geometry) -> Void
    ) {
        for shape in shape.children {
            if shape.hasSelectableChildren {
                fn(shape)
                enumerateGeometries(in: shape, with: fn)
            } else if shape.isSelectable {
                fn(shape)
            }
        }
    }

    private func geometryName(
        for geometry: Geometry,
        in countsByType: inout [String: Int]
    ) -> String {
        let typeName = geometry.type.logDescription
        var count = countsByType[typeName] ?? 0
        count += 1
        countsByType[typeName] = count
        if let name = geometry.name, !name.isEmpty {
            return "\(name) (\(typeName.capitalized) \(count))"
        }
        return "\(typeName.capitalized) \(count)"
    }

    private func geometryName(for geometry: Geometry) -> String {
        var countsByType = [String: Int]()
        let selectableGeometries = self.selectableGeometries
        for shape in selectableGeometries {
            let name = geometryName(for: shape, in: &countsByType)
            if shape === geometry {
                return name
            }
        }
        return ""
    }

    private var selectableGeometries: [Geometry] {
        var geometries = [Geometry]()
        enumerateGeometries(in: geometry) { geometry in
            if geometry.isSelectable {
                geometries.append(geometry)
            }
        }
        return geometries
    }

    func selectShape(at index: Int, andSpeakName speakName: Bool = false) {
        let selectableGeometries = self.selectableGeometries
        guard selectableGeometries.indices.contains(index) else {
            return
        }
        let shape = selectableGeometries[index]
        if speakName {
            voiceOver(geometryName(for: shape))
        }
        viewController?.selectGeometry(shape.scnNode)
    }

    func selectNextShape() {
        let selectableGeometries = self.selectableGeometries
        if let selectedGeometry = selectedGeometry,
           let index = selectableGeometries.firstIndex(where: {
               $0 === selectedGeometry
           })
        {
            let index = (index + 1) % selectableGeometries.count
            selectShape(at: index, andSpeakName: true)
        } else {
            selectShape(at: 0, andSpeakName: true)
        }
    }

    func selectPreviousShape() {
        let selectableGeometries = self.selectableGeometries
        if let selectedGeometry = selectedGeometry,
           let index = selectableGeometries.firstIndex(where: {
               $0 === selectedGeometry
           })
        {
            let index = index > 0 ? index - 1 : selectableGeometries.count - 1
            selectShape(at: index, andSpeakName: true)
        } else {
            selectShape(at: selectableGeometries.count - 1, andSpeakName: true)
        }
    }

    func clearSelection() {
        voiceOver("Deselected")
        viewController?.selectGeometry(nil)
    }

    @IBAction func selectShapes(_: NSMenuItem) {
        // Does nothing
    }

    @IBAction func selectShape(_ menuItem: NSMenuItem) {
        if menuItem.tag > 0 {
            selectShape(at: menuItem.tag - 1)
        }
    }

    @IBAction func clearSelection(_: NSMenuItem) {
        viewController?.selectGeometry(nil)
    }

    // MARK: Cameras

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    private var camerasMenu: NSMenu?

    private func configureCameraMenu(_ menu: NSMenu) {
        while menu.item(at: 0)?.isSeparatorItem == false {
            menu.removeItem(at: 0)
        }
        for (i, camera) in cameras.enumerated() {
            let menuItem = menu.insertItem(
                withTitle: camera.name,
                action: #selector(selectCamera(_:)),
                keyEquivalent: i < 9 ? "\(i + 1)" : "",
                at: i
            )
            menuItem.tag = i
            menuItem.keyEquivalentModifierMask = .command
        }
    }

    @IBAction func selectCameras(_: NSMenuItem) {
        // Does nothing
    }

    @IBAction func selectCamera(_ menuItem: NSMenuItem) {
        if !selectCamera(at: menuItem.tag) {
            NSSound.beep()
        }
    }

    @IBAction func copyCamera(_: NSMenuItem) {
        viewController?.copyCamera()
    }

    @IBAction func showWireframe(_: NSMenuItem) {
        showWireframe.toggle()
    }

    @IBAction func showAxes(_: NSMenuItem) {
        showAxes.toggle()
    }

    @IBAction func setOrthographic(_: NSMenuItem) {
        isOrthographic.toggle()
    }

    // MARK: Menus

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showWireframe(_:)):
            menuItem.state = showWireframe ? .on : .off
        case #selector(showAxes(_:)):
            menuItem.state = showAxes ? .on : .off
        case #selector(setOrthographic(_:)):
            menuItem.state = camera.isOrthographic ?? isOrthographic ? .on : .off
            return camera.isOrthographic == nil
        case #selector(selectCamera(_:)) where menuItem.tag < cameras.count:
            if camera == cameras[menuItem.tag] {
                menuItem.state = cameraHasMoved ? .mixed : .on
            } else {
                menuItem.state = (camera == cameras[menuItem.tag]) ? .on : .off
            }
        case #selector(selectShapes(_:)):
            if let submenu = menuItem.submenu {
                selectMenu = submenu
                var index = 0, countsByType = [String: Int]()
                _ = configureSelectMenu(
                    submenu,
                    for: geometry,
                    with: &index,
                    countsByType: &countsByType
                )
                return submenu.numberOfItems != 0
            }
        case #selector(selectCameras(_:)):
            menuItem.title = "Camera (\(camera.name))"
            camerasMenu = menuItem.submenu
            camerasMenu.map(configureCameraMenu)
        case #selector(clearSelection(_:)):
            return selectedGeometry != nil
        case #selector(showModelInfo(_:)):
            menuItem.title = selectedGeometry == nil ?
                "Scene Info" : "Selected Shape Info"
        default:
            break
        }
        return super.validateMenuItem(menuItem)
    }
}

private extension Geometry {
    var isSelectable: Bool {
        switch type {
        case .cone, .cylinder, .sphere, .cube, .mesh,
             .extrude, .lathe, .loft, .fill, .hull,
             .union, .difference, .intersection, .xor, .stencil,
             .path:
            return true
        case .camera, .light, .group:
            return false
        }
    }

    var hasSelectableChildren: Bool {
        switch type {
        case .group:
            return true
        case .cone, .cylinder, .sphere, .cube, .mesh,
             .extrude, .lathe, .loft, .fill,
             .path, .camera, .light:
            return false
        case .hull, .union, .difference, .intersection, .xor, .stencil:
            return childDebug
        }
    }
}

extension NSView {
    var contentScaleFactor: CGFloat {
        window?.backingScaleFactor ?? 1
    }
}
