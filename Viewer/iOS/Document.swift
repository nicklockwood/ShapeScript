//
//  Document.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript
import UIKit
import UniformTypeIdentifiers

final class Document: UIDocument, @preconcurrency DocumentProtocol, @unchecked Sendable {
    static let backgroundColor: UIColor = UIColor { traits in
        #if os(visionOS)
        .clear
        #else
        .init(white: traits.userInterfaceStyle == .dark ? 0.15 : 0.625, alpha: 1)
        #endif
    }

    var documentFileURL: URL? {
        fileURL
    }

    let cache = GeometryCache()
    private(set) var fileMonitor: FileMonitor?

    weak var viewController: DocumentViewController?

    var scene: Scene? {
        didSet {
            perform(#selector(updateCamerasAndViews), on: .main, with: nil, waitUntilDone: false)
        }
    }

    var loadingProgress: LoadingProgress? {
        didSet {
            perform(#selector(updateViewsFromCallback), on: .main, with: nil, waitUntilDone: false)
        }
    }

    var rerenderRequired: Bool = false
    private var observer: Any?
    private weak var saveTimer: Timer?

    var sourceString: String = "" {
        didSet {
            perform(#selector(sourceStringDidChange), on: .main, with: nil, waitUntilDone: false)
        }
    }

    var errorMessage: NSAttributedString?
    var error: ProgramError? {
        didSet { errorMessage = error?.message(with: sourceString) }
    }

    func scheduleAutosave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(autosaveFromTimer),
            userInfo: nil,
            repeats: false
        )
    }

    var cameras: [Camera] = CameraType.allCases.map {
        Camera(type: $0)
    }

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        self.fileMonitor = FileMonitor(url) { [weak self] url in
            try self?.read(from: url)
        }

        // Observe settings changes.
        self.observer = NotificationCenter.default.addObserver(
            forName: .settingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.perform(#selector(Document.settingsUpdated), on: .main, with: nil, waitUntilDone: false)
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    @MainActor func didMove(to url: URL) {
        presentedItemDidMove(to: url)
        fileMonitor?.move(to: url)
    }

    @MainActor func proposedName(for title: String) -> String? {
        let fileName = title.sanitizedFileName
        guard !fileName.isEmpty, !fileName.contains(":") else {
            return nil
        }

        let baseName = (fileName as NSString).deletingPathExtension
        guard !baseName.isEmpty, !baseName.hasPrefix(".") else {
            return nil
        }
        return baseName
    }

    @available(iOS 16.0, *)
    @MainActor func renameAndRefresh(
        proposedName: String,
        sourceViewController: SourceViewController?,
        completion: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) {
        guard proposedName != fileURL.displayBaseName else {
            completion(.success(()))
            return
        }

        guard let documentBrowser = UIApplication.shared.documentBrowserViewController else {
            completion(.failure(CocoaError(.fileWriteUnknown)))
            return
        }

        documentBrowser.renameDocument(at: fileURL, proposedName: proposedName) {
            [weak self, weak sourceViewController] finalURL, error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                } else if let finalURL, let self {
                    self.didMove(to: finalURL)
                    self.refreshAfterRename(sourceViewController: sourceViewController)
                    completion(.success(()))
                } else {
                    completion(.failure(CocoaError(.fileWriteUnknown)))
                }
            }
        }
    }

    @MainActor private func refreshAfterRename(sourceViewController: SourceViewController?) {
        SourceDocumentRegistry.register(self, for: fileURL)
        viewController?.updateSceneTitle()
        viewController?.updateModals()
        sourceViewController?.refreshAfterDocumentRename()

        UIApplication.shared.connectedScenes
            .compactMap { $0.delegate as? SourceSceneDelegate }
            .filter { $0.sourceViewController !== sourceViewController }
            .forEach { $0.load(fileURL, document: self) }
    }

    @MainActor @objc private func updateCamerasAndViews() {
        updateCameras()
        updateViews()
    }

    @MainActor @objc private func updateViewsFromCallback() {
        updateViews()
    }

    @MainActor @objc private func sourceStringDidChange() {
        if viewController != nil {
            didUpdateSource()
        }
    }

    @objc private func autosaveFromTimer() {
        autosave { [weak self] _ in
            self?.fileMonitor?.markUpdated()
        }
    }

    @MainActor @objc private func settingsUpdated() {
        rerender()
        updateViews()
    }

    override func load(fromContents contents: Any, ofType _: String?) throws {
        if let data = contents as? Data {
            try load(data, fileURL: fileURL)
        }
    }

    override func contents(forType _: String) throws -> Any {
        Data(sourceString.utf8)
    }

    override func close(completionHandler: ((Bool) -> Void)? = nil) {
        loadingProgress?.cancel()
        nonisolated(unsafe) let completionHandler = completionHandler
        super.close { hasChanges in
            completionHandler?(hasChanges)
            for resource in self.securityScopedResources {
                resource.stopAccessingSecurityScopedResource()
            }
        }
    }

    @MainActor func grantAccess() {
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
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        urls.forEach(bookmarkURL)
        try? read(from: fileURL)
    }
}

private extension String {
    var sanitizedFileName: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
