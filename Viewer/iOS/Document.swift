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
    private(set) var fileMonitor: FileMonitor?

    weak var viewController: DocumentViewController?

    var scene: Scene? {
        didSet {
            updateCameras()
            updatePresets()
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
    var presets: [Export] = []

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        fileMonitor = FileMonitor(url) { [weak self] url in
            try self?.read(from: url)
        }
    }

    override func load(fromContents contents: Any, ofType _: String?) throws {
        if let data = contents as? Data {
            try load(data, fileURL: fileURL)
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
