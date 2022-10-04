//
//  Document.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import SceneKit
import ShapeScript
import UIKit
import UniformTypeIdentifiers

class Document: UIDocument {
    static let backgroundColor: UIColor = UIColor { traits in
        .init(Color(traits.userInterfaceStyle == .dark ? 0.15 : 0.625))
    }

    let cache = GeometryCache()
    let settings = Settings.shared
    var securityScopedResources = Set<URL>()

    weak var viewController: DocumentViewController?

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
    var sourceString: String = ""

    override func load(fromContents contents: Any, ofType _: String?) throws {
        guard let data = contents as? Data,
              let input = String(data: data, encoding: .utf8)
        else { return }

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
                    if input != self.sourceString {
                        self.sourceString = input
                        viewController.dismissModals()
                    }
                    viewController.showConsole = false
                    viewController.clearLog()
                }
            case let .partial(scene), let .success(scene):
                self.errorMessage = nil
                self.accessErrorURL = nil
                self.scene = scene
            case let .failure(error):
                let message = error.message(with: input)
                Swift.print(message.string)
                self.errorMessage = message
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

    override func close(completionHandler: ((Bool) -> Void)? = nil) {
        loadingProgress?.cancel()
        super.close { hasChanges in
            completionHandler?(hasChanges)
            self.securityScopedResources.forEach {
                $0.stopAccessingSecurityScopedResource()
            }
        }
    }

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    var linkedResources = Set<URL>()

    func grantAccess() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.directoryURL = accessErrorURL
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        viewController?.present(picker, animated: true)
    }
}

extension Document: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL)
    {
        bookmarkURL(url)
        try? read(from: fileURL)
    }
}
