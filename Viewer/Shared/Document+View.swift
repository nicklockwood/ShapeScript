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

    var cameraHasMoved: Bool {
        viewController?.cameraHasMoved ?? false
    }

    func cameraConfig(for scnView: SCNView, contentsScale: CGFloat) -> String? {
        guard let scnCameraNode = scnView.pointOfView,
              let geometry = try? Geometry(scnCameraNode),
              case var .camera(camera) = geometry.type
        else {
            return nil
        }

        // Set additional camera properties
        camera.width = Double(scnView.frame.width * contentsScale)
        camera.height = Double(scnView.frame.height * contentsScale)
        camera.background = self.camera.background

        // Use current camera name (if custom and set)
        var fields = [String]()
        if let name = self.camera.geometry?.name {
            fields.append("name \(name.nestedLogDescription)")
        }

        // Geometry attributes
        let epsilon = 0.0001
        let transform = geometry.transform
        let scale = transform.scale
        if abs(scale.x - scale.y) < epsilon, abs(scale.y - scale.z) < epsilon {
            if abs(scale.x - 1) > epsilon {
                fields.append("size \(scale.x.logDescription)")
            }
        } else {
            fields.append("size \(scale.logDescription)")
        }
        if transform.offset != .zero {
            fields.append("position \(transform.offset.logDescription)")
        }
        if transform.rotation != .identity {
            fields.append("orientation \(transform.rotation.logDescription)")
        }

        // Camera attributes
        if let fov = camera.fov, abs(fov.degrees - 60) > epsilon {
            fields.append("fov \(fov.logDescription)")
        }
        if let width = camera.width {
            fields.append("width \(width.logDescription)")
        }
        if let height = camera.height {
            fields.append("height \(height.logDescription)")
        }
        if let background = camera.background {
            switch background {
            case let .color(color):
                var components = color.components
                if color.a == 1 {
                    components.removeLast()
                }
                if color.r == color.b, color.b == color.g {
                    components = [color.r]
                }
                let string = components.map { $0.logDescription }.joined(separator: " ")
                fields.append("background \(string)")
            case let .texture(texture):
                if case let .file(name, _) = texture {
                    fields.append("background \(name.nestedLogDescription)")
                }
            }
        }

        return """
        camera {
            \(fields.joined(separator: "\n    "))
        }
        """
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

    func updateViews() {
        guard let viewController = viewController else {
            return
        }
        viewController.isLoading = (loadingProgress?.inProgress == true)
        viewController.background = camera.background ?? scene?.background
        viewController.geometry = geometry
        viewController.errorMessage = errorMessage
        viewController.showAccessButton = (errorMessage != nil && accessErrorURL != nil)
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
                if error.isPermissionError {
                    self.accessErrorURL = error.fileURL
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
}
