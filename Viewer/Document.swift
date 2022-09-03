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
        if #available(macOS 10.14, *) {
            if Thread.isMainThread {
                NSAppearance.current = NSApp.effectiveAppearance
            } else {
                DispatchQueue.main.sync {
                    NSAppearance.current = NSApp.effectiveAppearance
                }
            }
        }
        return .underPageBackgroundColor
    }

    let cache = GeometryCache()
    let settings = Settings.shared
    var linkedResources = Set<URL>()
    var securityScopedResources = Set<URL>()

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
        didSet {
            updateViews()
        }
    }

    var errorMessage: NSAttributedString?
    var accessErrorURL: URL?

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    override var fileURL: URL? {
        didSet {
            startObservingFileChangesIfPossible()
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
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController
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
    }

    override func close() {
        super.close()
        loadingProgress?.cancel()
        _timer?.invalidate()
        securityScopedResources.forEach {
            $0.stopAccessingSecurityScopedResource()
        }
    }

    override func read(from url: URL, ofType _: String) throws {
        let input = try String(contentsOf: url, encoding: .utf8)
        linkedResources.removeAll()
        if let progress = loadingProgress, progress.inProgress {
            Swift.print("[\(progress.id)] cancelling...")
            progress.cancel()
        }
        let camera = self.camera
        let showWireframe = self.showWireframe
        loadingProgress = LoadingProgress { [weak self] status in
            guard let self = self else {
                return
            }
            switch status {
            case .waiting:
                if let viewController = self.viewController {
                    viewController.showConsole = false
                    viewController.clearLog()
                }
            case let .partial(scene), let .success(scene):
                self.errorMessage = nil
                self.accessErrorURL = nil
                self.scene = scene
            case let .failure(error):
                self.errorMessage = error.message(with: input)
                if case let .fileAccessRestricted(_, url)? = (error as? RuntimeError)?.type {
                    self.accessErrorURL = url
                } else {
                    self.accessErrorURL = nil
                }
                self.updateViews()
            case .cancelled:
                break
            }
        }

        loadingProgress?.dispatch { [cache] progress in
            func logCancelled() -> Bool {
                if progress.isCancelled {
                    Swift.print("[\(progress.id)] cancelled")
                    return true
                }
                return false
            }

            let start = CFAbsoluteTimeGetCurrent()
            Swift.print("[\(progress.id)] starting...")
            if logCancelled() {
                return
            }

            let program = try parse(input)
            let parsed = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] parsing: %.2fs", parsed - start))
            if logCancelled() {
                return
            }

            let scene = try evaluate(program, delegate: self, cache: cache, isCancelled: {
                progress.isCancelled
            })
            let evaluated = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] evaluating: %.2fs", evaluated - parsed))
            if logCancelled() {
                return
            }

            // Clear errors and previous geometry
            progress.setStatus(.partial(.empty))

            let minUpdatePeriod: TimeInterval = 0.1
            var lastUpdate = CFAbsoluteTimeGetCurrent() - minUpdatePeriod
            let options = scene.outputOptions(
                for: camera.settings,
                backgroundColor: Color(Self.backgroundColor),
                wireframe: showWireframe
            )
            _ = scene.build {
                if progress.isCancelled {
                    return false
                }
                let time = CFAbsoluteTimeGetCurrent()
                if time - lastUpdate > minUpdatePeriod {
                    Swift.print(String(format: "[\(progress.id)] rendering..."))
                    scene.scnBuild(with: options)
                    progress.setStatus(.partial(scene))
                    lastUpdate = time
                }
                return true
            }

            if logCancelled() {
                return
            }

            let done = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] geometry: %.2fs", done - evaluated))
            scene.scnBuild(with: options)
            progress.setStatus(.success(scene))

            let end = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] total: %.2fs", end - start))
        }
    }

    private var _modified: TimeInterval = 0
    private var _timer: Timer?

    private func startObservingFileChangesIfPossible() {
        // cancel previous observer
        _timer?.invalidate()

        // check file exists
        guard let url = fileURL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        func getModifiedDate(_ url: URL) -> TimeInterval? {
            let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
            return date.map { $0.timeIntervalSinceReferenceDate }
        }

        func fileIsModified(_ url: URL) -> Bool {
            guard let newDate = getModifiedDate(url), newDate > _modified else {
                return false
            }
            return true
        }

        // set modified date
        _modified = Date.timeIntervalSinceReferenceDate

        // start watching
        _timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else {
                return
            }
            guard getModifiedDate(url) != nil else {
                self._timer?.invalidate()
                self._timer = nil
                return
            }
            var isModified = false
            for u in [url] + Array(self.linkedResources) {
                isModified = isModified || fileIsModified(u)
            }
            guard isModified else {
                return
            }
            self._modified = Date.timeIntervalSinceReferenceDate
            _ = try? self.read(from: url, ofType: url.pathExtension)
        }
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
        openFileInEditor(selectedGeometry?.sourceLocation?.file ?? fileURL)
    }

    @IBAction func grantAccess(_: Any?) {
        let dialog = NSOpenPanel()
        dialog.title = "Grant Access"
        dialog.showsHiddenFiles = false
        dialog.directoryURL = accessErrorURL
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
            "Selected Object Info"
        } ?? "Model Info"
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

    private var camerasMenu: NSMenu?

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
        case #selector(selectCameras(_:)):
            menuItem.title = "Camera (\(camera.name))"
            camerasMenu = menuItem.submenu
            camerasMenu.map { configureCameraMenu($0, for: self) }
        default:
            break
        }
        return super.validateMenuItem(menuItem)
    }

    @IBAction func selectCameras(_: NSMenuItem) {
        // Does nothing
    }

    @IBAction func selectCamera(_ menuItem: NSMenuItem) {
        guard menuItem.tag < cameras.count else {
            NSSound.beep()
            return
        }
        let camera = cameras[menuItem.tag]
        if camera == self.camera {
            viewController?.resetCamera()
        } else {
            self.camera = camera
        }
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
}
