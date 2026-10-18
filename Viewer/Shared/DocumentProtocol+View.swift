//
//  DocumentProtocol+View.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 12/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import SceneKit
import ShapeScript

struct SelectionMenuEntry {
    let geometry: Geometry
    let title: String
    let isSelectable: Bool
    let children: [SelectionMenuEntry]
}

struct SelectionMenuContext {
    let entries: [SelectionMenuEntry]
    let lazySubmenus: Bool
}

private extension Double {
    static let parsed = 0.1
    static let evaluated = 0.2
    static let geometryBuilt = 0.9
}

@MainActor
extension DocumentProtocol {
    var settings: Settings { .shared }

    private var loadingIndicatorProgress: Double? {
        guard let loadingProgress else {
            return nil
        }
        switch loadingProgress.status {
        case let .partial(_, progress):
            return progress
        case .waiting:
            return 0
        case .success, .cancelled, .failure:
            return nil
        }
    }

    var fileName: String {
        documentFileURL?.lastPathComponent ?? "File"
    }

    var isEditable: Bool {
        documentFileURL.map {
            ($0.isShapeFile || $0.isCSGFile) &&
                FileManager.default.isWritableFile(atPath: $0.path) &&
                !$0.path.hasPrefix(Bundle.main.bundlePath)
        } ?? false
    }

    var errorURL: URL? {
        documentFileURL.flatMap { error?.shapeFileURL(relativeTo: $0) }
    }

    var geometry: Geometry {
        (scene ?? .empty).geometry
    }

    func rerender() {
        guard let loadingProgress, loadingProgress.didSucceed else {
            didUpdateSource()
            return
        }
        let cameraSettings = camera.settings
        let backgroundColor = Self.backgroundColor
        let showWireframe = showWireframe && viewController?.isQuickLook != true
        loadingProgress.dispatch { progress in
            if case let .success(scene) = progress.status,
               !scene.children.isEmpty
            {
                progress.setStatus(.partial(scene, .geometryBuilt))
                scene.scnBuild(with: scene.outputOptions(
                    for: cameraSettings,
                    backgroundColor: Color(backgroundColor),
                    wireframe: showWireframe
                ))
                progress.setStatus(.success(scene))
            }
        }
    }

    func updateViews() {
        guard let viewController else { return }
        let isLoading = loadingProgress?.inProgress == true
        viewController.isLoading = isLoading
        // Writing the success status's nil progress would hide immediately on iOS
        if loadingProgress?.didSucceed != true {
            viewController.renderProgress = loadingIndicatorProgress
        }
        viewController.background = camera.background ?? scene?.background
        viewController.setError(error, message: errorMessage)
        viewController.showAxes = showAxes
        viewController.isOrthographic = isOrthographic
        viewController.camera = camera
        viewController.refreshScene()
    }

    func didUpdateSource() {
        // Keep evaluation errors and their original source excerpt visible until
        // the new evaluation succeeds or supplies a replacement error.
        if error?.type == .fileAccess {
            error = nil
        }
        linkedResources.removeAll()
        if let progress = loadingProgress, progress.inProgress {
            Swift.print("[\(progress.id)] cancelling...")
            progress.cancel()
        }
        let cameraSettings = camera.settings
        let backgroundColor = Self.backgroundColor
        let showWireframe = showWireframe
        let fileURL = documentFileURL
        let input = sourceString
        let previousScene = scene ?? .empty
        loadingProgress = LoadingProgress { [weak self] status in
            guard let self else {
                return
            }
            if input != sourceString {
                if !status.isCancelledOrFailed {
                    didUpdateSource()
                }
                return
            }
            switch status {
            case .waiting:
                if let viewController {
                    viewController.renderProgress = loadingIndicatorProgress
                    viewController.clearLog()
                }
                updateViews()
            case let .partial(scene, _):
                self.scene = scene.with(zUp: zUp)
                viewController?.renderProgress = loadingIndicatorProgress
            case let .success(scene):
                if let viewController, !viewController.hasLog {
                    viewController.showConsole = false
                }
                error = nil
                self.scene = scene.with(zUp: zUp)
                viewController?.checkDocumentWarnings()
                viewController?.renderProgress = 1
                // Flush progress animation before indicator is hidden
                CATransaction.flush()
                viewController?.isLoading = false
                let loadingProgress = loadingProgress
                Task { @MainActor [weak self, weak loadingProgress] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self,
                          self.loadingProgress === loadingProgress,
                          self.loadingProgress?.didSucceed == true
                    else {
                        return
                    }
                    viewController?.renderProgress = nil
                }
            case let .failure(error):
                if let viewController, !viewController.hasLog {
                    viewController.showConsole = false
                }
                viewController?.renderProgress = nil
                self.error = error
                updateViews()
            case .cancelled:
                viewController?.renderProgress = nil
                viewController?.isLoading = false
            }
        }

        let refreshCache = refreshCacheOnReload
        refreshCacheOnReload = false
        loadingProgress?.dispatch { [cache] progress in
            try cache.withRefresh(refreshCache) {
                func logCancelled() -> Bool {
                    if progress.isCancelledOrFailed {
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
                progress.setStatus(.partial(previousScene, 0))

                let isCSG = fileURL?.isCSGFile ?? false
                let program = try isCSG ? nil : parse(input, at: fileURL)
                let parsed = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "[\(progress.id)] parsing: %.2fs", parsed - start))
                if logCancelled() {
                    return
                }
                progress.setStatus(.partial(previousScene, .parsed))

                let minUpdatePeriod: TimeInterval = 0.1
                let evaluationProgress = EvaluationProgress()
                @Sendable func scheduleEvaluationProgressUpdate() {
                    progress.schedule(after: minUpdatePeriod) {
                        guard !evaluationProgress.isFinished else {
                            return
                        }
                        guard progress.inProgress, !progress.isCancelledOrFailed else {
                            evaluationProgress.cancel()
                            return
                        }
                        let evaluationFraction = evaluationProgress.fractionCompleted ?? 0
                        let progressFraction = .parsed + evaluationFraction * (.evaluated - .parsed)
                        progress.setStatus(.partial(previousScene, progressFraction))
                        scheduleEvaluationProgressUpdate()
                    }
                }
                let scene: Scene
                let error: Error?
                if let program {
                    scheduleEvaluationProgressUpdate()
                    (scene, error) = evaluate(
                        program,
                        preview: true,
                        delegate: self,
                        cache: cache,
                        progress: evaluationProgress
                    )
                } else {
                    do {
                        scene = try Scene(csgString: input, at: fileURL, cache: cache, delegate: self, isCancelled: {
                            progress.isCancelledOrFailed
                        })
                    } catch let error as CSGImportError {
                        throw ProgramError(error, in: input)
                    }
                    error = nil
                }
                let evaluated = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "[\(progress.id)] evaluating: %.2fs", evaluated - parsed))
                if logCancelled() {
                    return
                }
                progress.setStatus(.partial(previousScene, .evaluated))

                let renderProgress = RenderProgress()
                let options = scene.outputOptions(
                    for: cameraSettings,
                    backgroundColor: Color(backgroundColor),
                    wireframe: showWireframe
                )

                // Clear errors and previous geometry
                progress.setStatus(.partial(.empty, .evaluated))

                @Sendable func scheduleRenderProgressUpdate() {
                    progress.schedule(after: minUpdatePeriod) {
                        guard progress.inProgress, !renderProgress.isFinished else {
                            return
                        }
                        guard !progress.isCancelledOrFailed else {
                            renderProgress.cancel()
                            return
                        }
                        Swift.print(String(format: "[\(progress.id)] rendering..."))
                        scene.scnBuild(with: options)
                        guard !renderProgress.isFinished else {
                            return
                        }
                        guard progress.inProgress, !progress.isCancelledOrFailed else {
                            renderProgress.cancel()
                            return
                        }
                        let geometryFraction = renderProgress.fractionCompleted ?? 0
                        let progressFraction = .evaluated + geometryFraction * (.geometryBuilt - .evaluated)
                        progress.setStatus(.partial(scene, progressFraction))
                        scheduleRenderProgressUpdate()
                    }
                }
                scheduleRenderProgressUpdate()
                _ = scene.build(progress: renderProgress)

                if logCancelled() {
                    return
                }

                let done = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "[\(progress.id)] geometry: %.2fs", done - evaluated))
                // A preview update may still be converting the same meshes. Finish
                // on its serial queue so SceneKit conversion never overlaps.
                progress.performUpdate {
                    progress.setStatus(.partial(scene, .geometryBuilt))
                    scene.scnBuild(with: options)
                }

                // Show error
                if let error {
                    progress.setStatus(.partial(scene, .geometryBuilt))
                    throw error
                }

                progress.setStatus(.success(scene))
                let end = CFAbsoluteTimeGetCurrent()
                Swift.print(String(format: "[\(progress.id)] total: %.2fs", end - start))
            }
        }
    }

    // MARK: Camera

    var zUp: Bool {
        documentFileURL?.isCSGFile ?? false
    }

    var showWireframe: Bool {
        get { settings.value(for: #function, in: self) ?? false }
        set {
            settings.set(newValue, for: #function, in: self)
            rerender()
        }
    }

    var showAxes: Bool {
        get { settings.value(for: #function, in: self) ?? false }
        set {
            settings.set(newValue, for: #function, in: self)
            updateViews()
        }
    }

    var isOrthographic: Bool {
        get {
            settings.value(for: #function, in: self) ?? false
        }
        set {
            settings.set(newValue, for: #function, in: self)
            updateViews()
        }
    }

    var camera: Camera {
        get {
            let type: CameraType? = settings.value(for: #function, in: self)
            var camera = cameras.first(where: { $0.type == type }) ??
                Camera(bounds: scene?.visibleBounds ?? .empty, zUp: zUp)
            camera.zUp = zUp
            return camera
        }
        set {
            settings.set(newValue.type, for: #function, in: self)
            updateViews()
        }
    }

    var cameraHasMoved: Bool {
        viewController?.cameraHasMoved ?? false
    }

    func cameraGeometry(for scnView: SCNView) -> Geometry? {
        guard let scnCameraNode = scnView.pointOfView,
              let geometry = try? Geometry(scnCameraNode),
              case var .camera(camera) = geometry.type
        else {
            return nil
        }
        let contentsScale = scnView.contentScaleFactor
        camera.width = Int(exactly: (scnView.frame.width * contentsScale).rounded())
        camera.height = Int(exactly: (scnView.frame.height * contentsScale).rounded())
        camera.background = self.camera.background
        return Geometry(
            type: .camera(camera),
            name: self.camera.geometry?.name,
            transform: geometry.transform,
            material: .default,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
    }

    func cameraConfig(for scnView: SCNView) -> String? {
        cameraGeometry(for: scnView).logDescription
    }

    func updateCameras() {
        let customCameras = scene?.cameras ?? []
        if !customCameras.isEmpty || loadingProgress?.didSucceed != false {
            let oldCameras = cameras
            cameras = CameraType.allCases.map {
                Camera(type: $0, zUp: zUp)
            } + customCameras.enumerated().map { i, geometry in
                Camera(geometry: geometry, index: i, zUp: zUp)
            }
            if !oldCameras.isEmpty {
                var didUpdateCamera = false
                for (old, new) in zip(oldCameras, cameras)
                    where old.type != new.type || old.settings != new.settings
                {
                    camera = new
                    didUpdateCamera = true
                    break
                }
                if !didUpdateCamera, cameras.count > oldCameras.count {
                    camera = cameras[oldCameras.count]
                }
            }
        }
    }

    func selectCamera(at index: Int) -> Bool {
        guard cameras.indices.contains(index) else {
            return false
        }
        let camera = cameras[index]
        if camera == self.camera {
            self.camera = camera
            viewController?.resetCamera()
        } else {
            self.camera = camera
        }
        return true
    }

    // MARK: Selection

    var selectedGeometry: Geometry? {
        viewController?.selectedGeometry
    }

    func clearSelection() {
        voiceOver("Deselected")
        viewController?.selectGeometry(nil)
    }

    func selectShape(at index: Int, andSpeakName speakName: Bool = false) {
        let selectableGeometries = selectableGeometries
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
        let selectableGeometries = selectableGeometries
        if let selectedGeometry,
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
        let selectableGeometries = selectableGeometries
        if let selectedGeometry,
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

    private func geometryName(for geometry: Geometry) -> String {
        geometryNames(for: [ObjectIdentifier(geometry)])[ObjectIdentifier(geometry)] ?? ""
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

    private func titledSelectionMenuEntries(
        _ entries: [SelectionMenuEntry]
    ) -> [SelectionMenuEntry] {
        var menuGeometries = Set<ObjectIdentifier>()

        func enumerateSelectionMenuEntries(in entries: [SelectionMenuEntry]) {
            for entry in entries {
                menuGeometries.insert(ObjectIdentifier(entry.geometry))
                enumerateSelectionMenuEntries(in: entry.children)
            }
        }

        enumerateSelectionMenuEntries(in: entries)
        let namesByGeometry = geometryNames(for: menuGeometries)

        func titled(_ entry: SelectionMenuEntry) -> SelectionMenuEntry {
            SelectionMenuEntry(
                geometry: entry.geometry,
                title: namesByGeometry[ObjectIdentifier(entry.geometry)] ?? "",
                isSelectable: entry.isSelectable,
                children: entry.children.map(titled)
            )
        }

        return entries.map(titled)
    }

    var selectionMenuEntries: [SelectionMenuEntry] {
        titledSelectionMenuEntries(geometry.rawSelectionMenuEntries)
    }

    func selectionMenuEntries(for geometries: [Geometry]) -> [SelectionMenuEntry] {
        titledSelectionMenuEntries(geometry.rawSelectionMenuEntries(for: geometries))
    }

    private func geometryNames(for geometries: Set<ObjectIdentifier>) -> [ObjectIdentifier: String] {
        var countsByType = [String: Int]()
        var namesByGeometry = [ObjectIdentifier: String]()

        func enumerateGeometryNames(in geometry: Geometry) {
            for child in geometry.children {
                if child.isVisibleInSelectionMenu {
                    let id = ObjectIdentifier(child)
                    let name = geometryName(for: child, in: &countsByType)
                    if geometries.contains(id) {
                        namesByGeometry[id] = name
                    }
                }
                enumerateGeometryNames(in: child)
            }
        }

        enumerateGeometryNames(in: geometry)
        return namesByGeometry
    }

    var selectableGeometries: [Geometry] {
        var geometries = [Geometry]()
        let focus = geometry.childIsFocused

        func enumerateSelectableGeometries(in shape: Geometry) {
            for shape in shape.children {
                guard shape.isVisibleForSelection(focus: focus) else {
                    continue
                }
                if shape.hasSelectableDescendants(focus: focus) {
                    geometries.append(shape)
                    enumerateSelectableGeometries(in: shape)
                } else if shape.isSelectable(focus: focus) {
                    geometries.append(shape)
                }
            }
        }

        enumerateSelectableGeometries(in: geometry)
        return geometries
    }
}

private extension Geometry {
    var rawSelectionMenuEntries: [SelectionMenuEntry] {
        rawSelectionMenuEntries(focus: childIsFocused)
    }

    func rawSelectionMenuEntries(focus: Bool) -> [SelectionMenuEntry] {
        children.flatMap { child -> [SelectionMenuEntry] in
            guard child.isVisibleInSelectionMenu else {
                return []
            }
            let childEntries = child.rawSelectionMenuEntries(focus: focus)
            if child.isSelectableInSelectionMenu(focus: focus) {
                return [SelectionMenuEntry(
                    geometry: child,
                    title: "",
                    isSelectable: true,
                    children: childEntries
                )]
            }
            return [SelectionMenuEntry(
                geometry: child,
                title: "",
                isSelectable: false,
                children: childEntries
            )]
        }
    }

    func rawSelectionMenuEntries(for geometries: [Geometry]) -> [SelectionMenuEntry] {
        let focus = childIsFocused
        let menuGeometries = geometries.filter(\.isVisibleInSelectionMenu)
        return menuGeometries.compactMap { geometry in
            guard !menuGeometries.contains(where: { geometry.isDescendant(of: $0) }) else {
                return nil
            }
            return geometry.selectionMenuEntry(in: menuGeometries, focus: focus)
        }
    }

    private func selectionMenuEntry(
        in geometries: [Geometry],
        focus: Bool
    ) -> SelectionMenuEntry? {
        let childGeometries = geometries.filter {
            $0 !== self && $0.isDescendant(of: self)
        }
        let childEntries = childGeometries.compactMap { geometry -> SelectionMenuEntry? in
            guard !childGeometries.contains(where: { geometry.isDescendant(of: $0) }) else {
                return nil
            }
            return geometry.selectionMenuEntry(in: childGeometries, focus: focus)
        }
        if isVisibleInSelectionMenu, isSelectableInSelectionMenu(focus: focus) {
            return SelectionMenuEntry(
                geometry: self,
                title: "",
                isSelectable: true,
                children: childEntries
            )
        }
        guard isVisibleInSelectionMenu, !isSelectable(focus: focus), !childEntries.isEmpty else {
            return nil
        }
        return SelectionMenuEntry(
            geometry: self,
            title: "",
            isSelectable: false,
            children: childEntries
        )
    }
}

extension Geometry {
    func isSelectableInSelectionMenu(focus: Bool) -> Bool {
        isSelectable(focus: focus) && isRenderedInScene(focus: focus)
    }

    func selectionMenuPath(root: Geometry) -> [Geometry] {
        var path = [Geometry]()
        var geometry: Geometry? = self
        while let current = geometry, current !== root {
            if current.isVisibleInSelectionMenu {
                path.append(current)
            }
            geometry = current.parent
        }
        return path.reversed()
    }
}

private extension Geometry {
    func isSelectable(focus: Bool) -> Bool {
        switch type {
        case .cone, .cylinder, .sphere, .icosphere, .cube, .mesh,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .circle, .square, .text, .path:
            !isHidden && (!focus || isFocused)
        case .camera, .light, .group:
            false
        }
    }

    func isVisibleForSelection(focus: Bool) -> Bool {
        !isHidden && (!focus || isFocused || childIsFocused)
    }

    var isVisibleInSelectionMenu: Bool {
        guard !isHidden else {
            return false
        }
        return switch type {
        case .camera, .light:
            false
        case .cone, .cylinder, .sphere, .icosphere, .cube, .mesh,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .circle, .square, .text, .path, .group:
            true
        }
    }

    func hasSelectableDescendants(focus: Bool) -> Bool {
        children.contains {
            $0.isVisibleForSelection(focus: focus) &&
                ($0.isSelectable(focus: focus) || $0.hasSelectableDescendants(focus: focus))
        }
    }
}

extension DocumentProtocol {
    func load(_ data: Data, fileURL: URL) throws {
        var nsString: NSString?
        _ = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [String.Encoding.utf8.rawValue],
                .likelyLanguageKey: "en",
            ],
            convertedString: &nsString,
            usedLossyConversion: nil
        )
        guard let input = nsString as String? else {
            throw RuntimeErrorType.fileParsingError(
                for: fileURL.lastPathComponent,
                at: fileURL,
                message: """
                The file '\(fileURL.lastPathComponent)' couldn’t be opened because the text \
                encoding of its contents can’t be determined.
                """
            )
        }
        if input != sourceString {
            if !sourceString.isEmpty {
                // Treat as edit
                formatVersion = ShapeScript.version
                clientVersion = appVersion
            }
            sourceString = input
            DispatchQueue.main.async { [weak self] in
                self?.viewController?.updateModals()
            }
        } else if viewController != nil {
            // Trigger reload anyway in case imported file has changed
            DispatchQueue.main.async { [self] in
                didUpdateSource()
            }
        }
    }

    @MainActor func refreshAfterDocumentURLChange(
        updateDocumentChrome: () -> Void = {},
        updateRelatedSourceViews: (URL) -> Void = { _ in }
    ) {
        if let documentFileURL {
            fileMonitor?.move(to: documentFileURL)
            updateRelatedSourceViews(documentFileURL)
        }
        updateDocumentChrome()
        updateViews()
    }

    var formatVersion: SemanticVersion? {
        get { settings.value(for: #function, in: self) }
        set { settings.set(newValue, for: #function, in: self) }
    }

    var clientVersion: SemanticVersion? {
        get { settings.value(for: #function, in: self) }
        set { settings.set(newValue, for: #function, in: self) }
    }
}
