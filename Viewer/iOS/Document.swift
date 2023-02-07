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
    var error: ProgramError?
    var rerenderRequired: Bool = false
    private var observer: Any?
    private weak var saveTimer: Timer?

    var sourceString: String? {
        didSet {
            if oldValue == sourceString {
                return
            } else if oldValue != nil {
                updateChangeCount(.done)
                if viewController == nil {
                    saveTimer?.invalidate()
                    saveTimer = Timer.scheduledTimer(
                        withTimeInterval: 1,
                        repeats: false
                    ) { [weak self] _ in
                        self?.autosave()
                    }
                }
            }
            if viewController != nil {
                didUpdateSource()
            }
        }
    }

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        fileMonitor = FileMonitor(url) { [weak self] url in
            try self?.read(from: url)
        }

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

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    override func load(fromContents contents: Any, ofType _: String?) throws {
        if let data = contents as? Data {
            try load(data, fileURL: fileURL)
        }
    }

    override func contents(forType _: String) throws -> Any {
        guard let data = sourceString?.data(using: .utf8) else {
            throw NSError(domain: "", code: 0) // Unknown error
        }
        return data
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
        picker.directoryURL = error?.accessErrorURL
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
