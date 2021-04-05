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

protocol ProgramError {
    var message: String { get }
    var range: Range<String.Index> { get }
    var hint: String? { get }
}

extension LexerError: ProgramError {}
extension ParserError: ProgramError {}
extension RuntimeError: ProgramError {}

class LoadingProgress {
    public enum Status {
        case waiting
        case partial([Geometry])
        case success([Geometry])
        case failure(Error)
        case cancelled
    }

    public typealias Observer = (Status) -> Void

    private var thread: Thread?
    private let observer: Observer
    private(set) var status: Status = .waiting

    init(_ observer: @escaping Observer) {
        self.observer = observer
        DispatchQueue.main.async {
            self.observer(self.status)
        }
    }

    public var isCancelled: Bool {
        if case .cancelled = status {
            return true
        }
        return false
    }

    public var inProgress: Bool {
        switch status {
        case .waiting, .partial:
            return true
        case .cancelled, .success, .failure:
            return false
        }
    }

    public var didSucceed: Bool {
        switch status {
        case .success:
            return true
        case .waiting, .partial, .cancelled, .failure:
            return false
        }
    }

    public func cancel() {
        guard inProgress else { return }
        setStatus(.cancelled)
    }

    fileprivate func setStatus(_ status: Status) {
        guard inProgress else { return }
        DispatchQueue.main.async {
            guard self.inProgress else { return }
            self.status = status
            self.observer(status)
        }
    }

    fileprivate func dispatch(_ block: @escaping () -> Void) {
        guard inProgress else { return }
        thread = Thread(block: block)
        thread?.stackSize = 4 * 1024 * 1024 * 1024
        thread?.start()
    }
}

class Document: NSDocument, EvaluationDelegate {
    var sceneViewControllers: [SceneViewController] {
        windowControllers.compactMap { $0.window?.contentViewController as? SceneViewController }
    }

    var geometry: Geometry? {
        didSet {
            updateViews()
        }
    }

    var selectedGeometry: Geometry? {
        for viewController in sceneViewControllers {
            if let selectedGeometry = viewController.selectedGeometry {
                return selectedGeometry
            }
        }
        return nil
    }

    var progress: LoadingProgress? {
        didSet {
            updateViews()
        }
    }

    var errorMessage: NSAttributedString?
    var accessErrorURL: URL?

    func updateViews() {
        for viewController in sceneViewControllers {
            viewController.isLoading = (progress?.inProgress == true)
            viewController.geometry = geometry
            viewController.errorMessage = errorMessage
            viewController.showAccessButton = (errorMessage != nil && accessErrorURL != nil)
            viewController.showWireframe = (NSApp.delegate as! AppDelegate).showWireframe
        }
    }

    override var fileURL: URL? {
        didSet {
            startObservingFileChangesIfPossible()
        }
    }

    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController
        addWindowController(windowController)
        updateViews()
    }

    private func message(for error: Error, in source: String) -> NSAttributedString {
        let errorType: String
        let message: String, range: Range<String.Index>?, hint: String?
        switch error {
        case let error as ProgramError:
            if let error = error as? RuntimeError, case .fileAccessRestricted = error.type {
                errorType = "Permission Required"
            } else {
                errorType = "Error"
            }
            message = error.message
            range = error.range
            hint = error.hint
        default:
            errorType = "Error"
            message = error.localizedDescription
            range = nil
            hint = nil
        }

        var location = "."
        var lineRange: Range<String.Index>?
        if let range = range {
            let (line, _) = source.lineAndColumn(at: range.lowerBound)
            location = " on line \(line)."
            let lr = source.lineRange(at: range.lowerBound)
            if !lr.isEmpty {
                lineRange = lr
            }
        }

        let errorMessage = NSMutableAttributedString()
        errorMessage.append(NSAttributedString(string: "\(errorType)\n\n", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
        ]))
        let body = message + location
        errorMessage.append(NSAttributedString(string: "\(body)\n\n", attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
        ]))
        if let lineRange = lineRange, let range = range,
           let font = NSFont(name: "Courier", size: 15)
        {
            let sourceLine = String(source[lineRange])
            let start = source.distance(from: lineRange.lowerBound, to: range.lowerBound)
            var length = source.distance(from: range.lowerBound, to: range.upperBound)
            length = max(min(length, source.distance(
                from: range.lowerBound,
                to: lineRange.upperBound
            )), 1)
            var underline = String(repeating: " ", count: max(0, start))
            underline += String(repeating: "^", count: length)
            errorMessage.append(NSAttributedString(
                string: "\(sourceLine)\n\(underline)\n\n",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: font,
                ]
            ))
        }
        if let hint = hint {
            errorMessage.append(NSAttributedString(string: "\(hint)\n\n", attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.7),
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            ]))
        }
        return errorMessage
    }

    override func read(from url: URL, ofType _: String) throws {
        let input = try String(contentsOf: url, encoding: .utf8)
        linkedResources.removeAll()
        self.progress?.cancel()
        let progress = LoadingProgress { [weak self] result in
            guard let self = self else {
                return
            }
            switch result {
            case .waiting:
                for viewController in self.sceneViewControllers {
                    viewController.showConsole = false
                    viewController.clearLog()
                }
            case let .partial(children), let .success(children):
                self.errorMessage = nil
                self.accessErrorURL = nil
                self.geometry = Geometry(
                    type: .none,
                    name: nil,
                    transform: .identity,
                    material: .default,
                    children: children,
                    sourceLocation: nil
                )
            case let .failure(error):
                self.errorMessage = self.message(for: error, in: input)
                if case let .fileAccessRestricted(_, url)? = (error as? RuntimeError)?.type {
                    self.accessErrorURL = url
                } else {
                    self.accessErrorURL = nil
                }
                self.updateViews()
            case .cancelled:
                Swift.print("cancelled")
            }
        }
        progress.dispatch { [weak progress] in
            guard let progress = progress, !progress.isCancelled else {
                return
            }
            let start = CFAbsoluteTimeGetCurrent()
            Swift.print("starting...")
            do {
                let program = try parse(input)
                let parsed = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "parsing: %.2fs", parsed - start))

                let geometries = try evaluate(program, delegate: self)
                let evaluated = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "evaluating: %.2fs", evaluated - parsed))

                // Clear errors and previous geometry
                progress.setStatus(.partial([]))

                var lastUpdate = CFAbsoluteTimeGetCurrent()
                for geometry in geometries {
                    // pre-generate geometry
                    _ = geometry.build {
                        if progress.isCancelled {
                            return false
                        }
                        let time = CFAbsoluteTimeGetCurrent()
                        if time - lastUpdate > 0.3 {
                            geometry.scnBuild()
                            progress.setStatus(.partial(geometries.map { $0.deepCopy() }))
                            lastUpdate = time
                        }
                        return true
                    }
                    if progress.isCancelled {
                        return
                    }
                    geometry.scnBuild()
                }
                if progress.isCancelled {
                    return
                }
                let done = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "geometry: %.2fs", done - evaluated))
                progress.setStatus(.success(geometries.map { $0.deepCopy() }))
            } catch {
                progress.setStatus(.failure(error))
            }
            if progress.isCancelled {
                return
            }
            let end = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "total: %.2fs", end - start))
        }
        self.progress = progress
    }

    private var _modified = 0
    private var _timer: Timer?

    private func startObservingFileChangesIfPossible() {
        // cancel previous observer
        _timer?.invalidate()

        // check file exists
        guard let url = fileURL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        func getModifiedDate(_ url: URL) -> Int? {
            let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
            return date.map { Int($0.timeIntervalSinceReferenceDate) }
        }

        func fileIsModified(_ url: URL) -> Bool {
            guard let newDate = getModifiedDate(url), newDate > _modified else {
                return false
            }
            return true
        }

        // set modified date
        _modified = Int(Date.timeIntervalSinceReferenceDate)

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
            for u in [url] + Array(self._securityScopedResources) {
                isModified = isModified || fileIsModified(u)
            }
            guard isModified else {
                return
            }
            self._modified = Int(Date.timeIntervalSinceReferenceDate)
            _ = try? self.read(from: url, ofType: url.pathExtension)
        }
    }

    deinit {
        _timer?.invalidate()
        _securityScopedResources.forEach {
            $0.stopAccessingSecurityScopedResource()
        }
    }

    @IBAction private func didSelectEditor(_ sender: NSPopUpButton) {
        handleEditorPopupAction(for: sender, in: windowForSheet)
    }

    private func openFileInEditor(_ fileURL: URL?) {
        guard let fileURL = fileURL else {
            return
        }
        guard Settings.shared.userDidChooseEditor, let editor = Settings.shared.selectedEditor else {
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
                    Settings.shared.userDidChooseEditor = true
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
            Settings.shared.userDidChooseEditor = false
            presentError(error)
        }
    }

    @IBAction func openInEditor(_: AnyObject) {
        openFileInEditor(selectedGeometry?.sourceLocation?.file ?? fileURL)
    }

    @IBAction func grantAccess(_: Any?) {
        guard let window = windowForSheet else {
            return
        }

        let dialog = NSOpenPanel()
        dialog.title = "Grant Access"
        dialog.showsHiddenFiles = false
        dialog.directoryURL = accessErrorURL
        dialog.canChooseDirectories = true
        dialog.beginSheetModal(for: window) { response in
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
        var fileURL: URL?

        if let selectedGeometry = self.selectedGeometry {
            var locationString = ""
            if let location = selectedGeometry.sourceLocation {
                locationString = "\nDefined on line \(location.line)"
                if let url = location.file {
                    fileURL = url
                    locationString += " in '\(url.lastPathComponent)'"
                }
            }

            let polygonCount: String
            let triangleCount: String
            let dimensions: String
            if progress?.didSucceed == true {
                polygonCount = String(selectedGeometry.polygonCount)
                triangleCount = String(selectedGeometry.triangleCount)
                dimensions = selectedGeometry.exactBounds.size.shortDescription
            } else {
                polygonCount = "calculating…"
                triangleCount = "calculating…"
                dimensions = "calculating…"
            }
            let nameString = selectedGeometry.name.flatMap {
                $0.isEmpty ? nil : "Name: \($0)"
            }
            actionSheet.messageText = "Selected Object Info"
            actionSheet.informativeText = [
                nameString,
                "Type: \(selectedGeometry.type)",
                "Children: \(selectedGeometry.children.count)",
                "Polygons: \(polygonCount)",
                "Triangles: \(triangleCount)",
                "Dimensions: \(dimensions)",
//                "Size: \(selectedGeometry.transform.scale.shortDescription)",
//                "Position: \(selectedGeometry.transform.offset.shortDescription)",
//                "Orientation: \(selectedGeometry.transform.rotation.shortDescription)",
                locationString,
            ].compactMap { $0 }.joined(separator: "\n")

        } else {
            let polygonCount: String
            let triangleCount: String
            let dimensions: String
            if progress?.didSucceed == true {
                polygonCount = String(geometry?.polygonCount ?? 0)
                triangleCount = String(geometry?.triangleCount ?? 0)
                dimensions = (geometry?.exactBounds ?? .empty).size.shortDescription
            } else {
                polygonCount = "calculating…"
                triangleCount = "calculating…"
                dimensions = "calculating…"
            }
            actionSheet.messageText = "Model Info"
            actionSheet.informativeText = """
            Objects: \(geometry?.objectCount ?? 0)
            Polygons: \(polygonCount)
            Triangles: \(triangleCount)
            Dimensions: \(dimensions)

            Imports: \(importedFileCount)
            Textures: \(textureCount)
            """
        }
        actionSheet.addButton(withTitle: "OK")
        actionSheet.addButton(withTitle: "Open in Editor")
        showSheet(actionSheet, in: windowForSheet) { response in
            switch response {
            case .alertSecondButtonReturn:
                self.openFileInEditor(fileURL ?? self.fileURL)
            default:
                break
            }
        }
    }

    var importedFileCount: Int {
        linkedResources.filter { $0.pathExtension == "shape" }.count
    }

    var textureCount: Int {
        linkedResources.filter { $0.pathExtension != "shape" }.count
    }

    // MARK: EvaluationDelegate

    var linkedResources = Set<URL>()

    func resolveURL(for path: String) -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: fileURL)
        linkedResources.insert(url)
        if let resolvedURL = resolveBookMark(for: url) {
            if resolvedURL.path != url.path {
                // File was moved, so return the original url (which will throw a file-not-found error)
                // TODO: we could handle this more gracefully by reporting that the file was moved
                return url
            }
            return resolvedURL
        } else {
            bookmarkURL(url)
        }
        return url
    }

    func importGeometry(for url: URL) throws -> Geometry? {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var url = url
        if isDirectory.boolValue {
            let newURL = url.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: newURL.path) {
                url = newURL
            }
        }
        let scene = try SCNScene(url: url, options: [
            .flattenScene: false,
            .createNormalsIfAbsent: true,
            .convertToYUp: true,
        ])
        return Geometry(scnNode: scene.rootNode)
    }

    func debugLog(_ values: [Any?]) {
        let line = values.map { $0.map {
            ($0 as? ShortDescribable).map { $0.shortDescription } ?? "\($0)"
        } ?? "nil" }.joined(separator: " ")
        Swift.print(line)
        DispatchQueue.main.async {
            for viewController in self.sceneViewControllers {
                viewController.showConsole = true
                viewController.appendLog(
                    NSAttributedString(string: line + "\n", attributes: [
                        .foregroundColor: NSColor.textColor,
                        .font: NSFont.systemFont(ofSize: 13),
                    ])
                )
            }
        }
    }

    // MARK: Sandbox support

    // For debugging purposes
    public func clearBookmarks() {
        UserDefaults.standard.removeObject(forKey: "SandboxBookmarks")
    }

    private var bookmarks: [String: Data] {
        set {
            UserDefaults.standard.set(newValue, forKey: "SandboxBookmarks")
        }
        get {
            UserDefaults.standard.dictionary(forKey: "SandboxBookmarks") as? [String: Data] ?? [:]
        }
    }

    private func bookmarkURL(_ url: URL) {
        // Create an app-scoped bookmark for the selected file or folder
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarks[url.absoluteString] = data
        }
    }

    private var _securityScopedResources = Set<URL>()

    private func accessSecurityScopedURL(_ resolvedURL: URL) -> Bool {
        if _securityScopedResources.contains(resolvedURL) {
            return true
        } else if resolvedURL.startAccessingSecurityScopedResource() {
            _securityScopedResources.insert(resolvedURL)
            return true
        }
        return false
    }

    private func resolveBookMark(for url: URL) -> URL? {
        let path = url.absoluteString
        guard let data = bookmarks[path] else {
            guard !url.pathExtension.isEmpty,
                  let directoryURL = resolveBookMark(for: url.deletingLastPathComponent())
            else {
                return nil
            }
            let resolvedURL = directoryURL.appendingPathComponent(url.lastPathComponent)
            return accessSecurityScopedURL(resolvedURL) ? resolvedURL : nil
        }
        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), accessSecurityScopedURL(resolvedURL) else {
            return nil
        }
        if isStale {
            bookmarkURL(resolvedURL)
        }
        return resolvedURL
    }
}
