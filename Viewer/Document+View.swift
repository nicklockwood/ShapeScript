//
//  Document+View.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 12/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
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
                for (old, new) in zip(oldCameras, cameras) where old != new {
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
}
