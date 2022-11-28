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
    var selectedGeometry: Geometry? {
        viewController?.selectedGeometry
    }

    var showWireframe: Bool {
        get { settings.value(for: #function, in: self) ?? false }
        set {
            settings.set(newValue, for: #function, in: self, andGlobally: true)
            rerender()
        }
    }

    var showAxes: Bool {
        get { settings.value(for: #function, in: self) ?? false }
        set {
            settings.set(newValue, for: #function, in: self, andGlobally: true)
            updateViews()
        }
    }

    var isOrthographic: Bool {
        get {
            settings.value(for: #function, in: self) ?? false
        }
        set {
            settings.set(newValue, for: #function, in: self, andGlobally: true)
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

    var preset: Export? {
        get {
            let name: String? = settings.value(for: #function, in: self)
            return presets.first(where: { $0.name == name })
        }
        set {
            settings.set(newValue?.name, for: #function, in: self)
        }
    }

    var cameraHasMoved: Bool {
        viewController?.cameraHasMoved ?? false
    }

    func cameraConfig(for scnView: SCNView, contentsScale: CGFloat) -> String? {
        guard let scnCameraNode = scnView.pointOfView,
              var geometry = try? Geometry(scnCameraNode),
              case var .camera(camera) = geometry.type
        else {
            return nil
        }
        camera.width = Double(scnView.frame.width * contentsScale)
        camera.height = Double(scnView.frame.height * contentsScale)
        camera.background = self.camera.background
        geometry = Geometry(
            type: .camera(camera),
            name: self.camera.geometry?.name,
            transform: geometry.transform,
            material: .default,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
        return geometry.logDescription
    }

    func rerender() {
        guard let loadingProgress = loadingProgress,
              loadingProgress.didSucceed
        else {
            return
        }
        let camera = self.camera
        let backgroundColor = Color(Self.backgroundColor)
        let showWireframe = self.showWireframe
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

    func updatePresets() {
        let customExports = scene?.exports ?? []
        if !customExports.isEmpty || loadingProgress?.didSucceed != false {
            let oldPresets = presets
            presets = customExports.enumerated().map { i, export in
                var export = export
                export.name = export.name.isEmpty ? "Preset \(i + 1)" : export.name
                return export
            }
            if !oldPresets.isEmpty {
                var didUpdatePreset = false
                for (old, new) in zip(oldPresets, presets) where old != new {
                    preset = new
                    didUpdatePreset = true
                    break
                }
                if !didUpdatePreset, presets.count > oldPresets.count {
                    preset = presets[oldPresets.count]
                }
            }
        }
    }

    func updateViews() {
        guard let viewController = viewController else {
            return
        }
        viewController.isLoading = (loadingProgress?.inProgress == true)
        viewController.background = camera.background ?? scene?.background
        viewController.geometry = geometry
        viewController.errorMessage = errorMessage
        viewController.showAccessButton = (errorMessage != nil && isAccessError)
        viewController.showAxes = showAxes
        viewController.isOrthographic = isOrthographic
        viewController.camera = camera
    }

    func load(_ data: Data, fileURL: URL) throws {
        var nsString: NSString?
        _ = NSString.stringEncoding(for: data, convertedString: &nsString, usedLossyConversion: nil)
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
        sourceString = input
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
                    if input != self.sourceString {
                        viewController.dismissModals()
                    }
                    viewController.showConsole = false
                    viewController.clearLog()
                }
            case let .partial(scene), let .success(scene):
                self.errorMessage = nil
                self.errorURL = nil
                self.isAccessError = false
                self.scene = scene
            case let .failure(error):
                self.errorMessage = error.message(with: input)
                if let accessErrorURL = error.accessErrorURL {
                    self.errorURL = accessErrorURL
                    self.isAccessError = true
                } else {
                    self.errorURL = error.shapeFileURL(relativeTo: fileURL)
                    self.isAccessError = false
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
}
