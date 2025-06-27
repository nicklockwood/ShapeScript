//
//  Document+View.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 12/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
import SceneKit
import ShapeScript

extension Document {
    var isEditable: Bool {
        let fileURL: URL? = fileURL
        return fileURL.map {
            FileManager.default.isWritableFile(atPath: $0.path) &&
                !$0.path.hasPrefix(Bundle.main.bundlePath)
        } ?? false
    }

    var errorURL: URL? {
        let fileURL: URL? = self.fileURL
        return fileURL.flatMap { error?.shapeFileURL(relativeTo: $0) }
    }

    var selectedGeometry: Geometry? {
        viewController?.selectedGeometry
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
            return cameras.first(where: { $0.type == type }) ?? .default
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
        camera.width = Double(scnView.frame.width * contentsScale)
        camera.height = Double(scnView.frame.height * contentsScale)
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

    func rerender() {
        guard let loadingProgress = loadingProgress,
              loadingProgress.didSucceed
        else {
            rerenderRequired = true
            return
        }
        let camera = self.camera
        let backgroundColor = Color(Self.backgroundColor)
        let showWireframe = self.showWireframe
        rerenderRequired = false
        loadingProgress.dispatch { progress in
            if case let .success(scene) = progress.status,
               !scene.children.isEmpty
            {
                progress.setStatus(.partial(scene))
                scene.scnBuild(with: scene.outputOptions(
                    for: camera.settings,
                    backgroundColor: backgroundColor,
                    wireframe: showWireframe
                ))
                progress.setStatus(.success(scene))
            }
        }
    }

    func updateCameras() {
        let customCameras = scene?.cameras ?? []
        if !customCameras.isEmpty || loadingProgress?.didSucceed != false {
            let oldCameras = cameras
            cameras = CameraType.allCases.map {
                Camera(type: $0)
            } + customCameras.enumerated().map { i, geometry in
                Camera(geometry: geometry, index: i)
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
            updateViews()
            viewController?.resetCamera()
        } else {
            self.camera = camera
        }
        return true
    }

    func updateViews() {
        guard let viewController = viewController else { return }
        viewController.isLoading = (loadingProgress?.inProgress == true)
        viewController.background = camera.background ?? scene?.background
        viewController.geometry = geometry
        viewController.setError(error, message: error?.message(with: sourceString))
        viewController.showAxes = showAxes
        viewController.isOrthographic = isOrthographic
        viewController.camera = camera
    }

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
            sourceString = input
            viewController?.updateModals()
        } else if viewController != nil {
            // Trigger reload anyway in case imported file has changed
            didUpdateSource()
        }
    }

    func didUpdateSource() {
        if let progress = loadingProgress, progress.inProgress {
            Swift.print("[\(progress.id)] cancelling...")
            progress.cancel()
        }
        let camera = self.camera
        let showWireframe = self.showWireframe
        let fileURL = fileURL
        let input = sourceString
        loadingProgress = LoadingProgress { [weak self] status in
            guard let self = self else {
                return
            }
            guard input == self.sourceString else {
                self.didUpdateSource()
                return
            }
            let wasFileAccessError = self.error?.type == .fileAccess
            self.error = nil // Error is invalid if sourceString has changed
            switch status {
            case .waiting:
                if let viewController = self.viewController {
                    viewController.showConsole = false
                    viewController.clearLog()
                }
                if wasFileAccessError {
                    updateViews()
                }
            case let .partial(scene), let .success(scene):
                self.error = nil
                self.scene = scene
                if case .success = status, self.rerenderRequired {
                    self.rerender()
                }
            case let .failure(error):
                self.error = error
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

            let program = try parse(input, at: fileURL)
            let parsed = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] parsing: %.2fs", parsed - start))
            if logCancelled() {
                return
            }

            let (scene, error) = evaluate(
                program,
                delegate: self,
                cache: cache,
                isCancelled: { progress.isCancelled }
            )
            let evaluated = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] evaluating: %.2fs", evaluated - parsed))
            if logCancelled() {
                return
            }

            // Check for too many lights
            let maxLights = 8
            let nonAmbientLights = scene.lights.filter {
                $0.light.map { SCNLight($0).type != .ambient } ?? false
            }
            if nonAmbientLights.count > maxLights {
                throw RuntimeError(.assertionFailure("""
                There is a maximum of \(maxLights) non-ambient lights per scene. \
                This scene has \(nonAmbientLights.count) lights
                """), at: nonAmbientLights[maxLights].sourceLocation?
                    .range(in: input) ?? input.startIndex ..< input.startIndex)
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

            // Show error
            if let error = error {
                progress.setStatus(.partial(scene))
                throw error
            }

            progress.setStatus(.success(scene))
            let end = CFAbsoluteTimeGetCurrent()
            Swift.print(String(format: "[\(progress.id)] total: %.2fs", end - start))
        }
    }
}
