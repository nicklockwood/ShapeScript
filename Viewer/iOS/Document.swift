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
    private var securityScopedResourceURL: URL
    private var securityScopedResourceAccessed: Bool

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
    private var saveTimer: Timer?
    private var isAutosaving = false
    private var autosaveQueued = false
    private var saveErrorAlertIsVisible = false

    var sourceString: String = "" {
        didSet {
            perform(#selector(sourceStringDidChange), on: .main, with: nil, waitUntilDone: false)
        }
    }

    var errorMessage: NSAttributedString?
    var error: ProgramError? {
        didSet { errorMessage = error?.message(with: sourceString) }
    }

    @MainActor func scheduleAutosave() {
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
        self.securityScopedResourceURL = url
        self.securityScopedResourceAccessed = url.startAccessingSecurityScopedResource()
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
            self?.perform(
                #selector(Document.settingsUpdated),
                on: .main,
                with: nil,
                waitUntilDone: false
            )
        }
    }

    deinit {
        saveTimer?.invalidate()
        observer.map(NotificationCenter.default.removeObserver)
        stopAccessingPrimarySecurityScopedResource()
    }

    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        perform(
            #selector(refreshAfterDocumentURLChange),
            on: .main,
            with: newURL as NSURL,
            waitUntilDone: false
        )
    }

    private func updatePrimarySecurityScopedResource(to url: URL) {
        guard url != securityScopedResourceURL else {
            return
        }
        stopAccessingPrimarySecurityScopedResource()
        securityScopedResourceURL = url
        securityScopedResourceAccessed = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingPrimarySecurityScopedResource() {
        guard securityScopedResourceAccessed else {
            return
        }
        securityScopedResourceURL.stopAccessingSecurityScopedResource()
        securityScopedResourceAccessed = false
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
        completion: @escaping @Sendable @MainActor (Result<Void, any Error>) -> Void
    ) {
        guard proposedName != fileURL.displayBaseName else {
            completion(.success(()))
            return
        }

        guard let documentBrowser = UIApplication.shared.documentBrowserViewController else {
            completion(.failure(CocoaError(.fileWriteUnknown)))
            return
        }

        documentBrowser.renameDocument(at: fileURL, proposedName: proposedName) { finalURL, error in
            let error = error.map { $0 as NSError }
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                } else if let finalURL {
                    self.presentedItemDidMove(to: finalURL)
                    completion(.success(()))
                } else {
                    completion(.failure(CocoaError(.fileWriteUnknown)))
                }
            }
        }
    }

    @MainActor @objc private func refreshAfterDocumentURLChange(_ newURL: NSURL) {
        updatePrimarySecurityScopedResource(to: newURL as URL)
        refreshAfterDocumentURLChange(
            updateDocumentChrome: { [weak self] in
                guard let self else { return }
                SourceDocumentRegistry.register(self, for: fileURL)
                viewController?.updateSceneTitle()
                viewController?.updateModals()
            },
            updateRelatedSourceViews: { [weak self] fileURL in
                guard let self else { return }
                UIApplication.shared.connectedScenes
                    .compactMap { $0.delegate as? SourceSceneDelegate }
                    .forEach { $0.load(fileURL, document: self) }
            }
        )
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

    @MainActor @objc private func autosaveFromTimer() {
        guard documentState != .closed, hasUnsavedChanges else {
            return
        }

        if isAutosaving {
            autosaveQueued = true
            return
        }

        isAutosaving = true
        autosaveQueued = false
        Task { @MainActor in
            let success = await autosaveDocument()
            isAutosaving = false
            if success {
                fileMonitor?.markUpdated()
                saveErrorAlertIsVisible = false
            } else {
                showSaveFailureAlert()
            }
            if autosaveQueued || hasUnsavedChanges {
                scheduleAutosave(after: success ? 1 : 5)
            }
        }
    }

    @MainActor private func autosaveDocument() async -> Bool {
        await withCheckedContinuation { continuation in
            autosave { success in
                continuation.resume(returning: success)
            }
        }
    }

    @MainActor private func scheduleAutosave(after delay: TimeInterval) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(
            timeInterval: delay,
            target: self,
            selector: #selector(autosaveFromTimer),
            userInfo: nil,
            repeats: false
        )
    }

    @MainActor private func showSaveFailureAlert() {
        guard !saveErrorAlertIsVisible else {
            return
        }
        saveErrorAlertIsVisible = true
        viewController?.presentError(NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Failed to save changes."]
        )) { [weak self] in
            self?.saveErrorAlertIsVisible = false
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
            self.stopAccessingPrimarySecurityScopedResource()
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
