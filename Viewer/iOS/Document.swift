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

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        startObservingFileChangesIfPossible()
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

    private var _modified: TimeInterval = 0
    private var _timer: Timer?

    private func startObservingFileChangesIfPossible() {
        // cancel previous observer
        _timer?.invalidate()

        // check file exists
        let url = fileURL
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
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
            for u in [url] + self.linkedResources {
                isModified = isModified || fileIsModified(u)
            }
            guard isModified else {
                return
            }
            self._modified = Date.timeIntervalSinceReferenceDate
            try? self.read(from: url)
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
