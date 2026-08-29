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
    var autosaveEnabled = true {
        didSet {
            guard autosaveEnabled != oldValue else {
                return
            }
            perform(
                #selector(autosaveModeDidChange),
                on: .main,
                with: nil,
                waitUntilDone: false
            )
        }
    }

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

    var showLineNumbers: Bool {
        get { Settings.shared.value(for: #function) ?? true }
        set { Settings.shared.set(newValue, for: #function) }
    }

    var linewrapEnabled: Bool {
        get { Settings.shared.value(for: #function) ?? false }
        set { Settings.shared.set(newValue, for: #function) }
    }

    var errorMessage: NSAttributedString?
    var error: ProgramError? {
        didSet { errorMessage = error?.message(with: sourceString) }
    }

    @MainActor func scheduleAutosave() {
        saveTimer?.invalidate()
        guard autosaveEnabled else {
            return
        }
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
        updateAutosaveState(for: url)
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

    private func updateAutosaveState(for url: URL) {
        autosaveEnabled = !url.isOnNetworkVolume
    }

    @MainActor @objc private func autosaveModeDidChange() {
        if autosaveEnabled {
            if hasUnsavedChanges {
                scheduleAutosave()
            }
        } else {
            saveTimer?.invalidate()
            saveTimer = nil
            autosaveQueued = false
        }
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
        let newURL = newURL as URL
        updatePrimarySecurityScopedResource(to: newURL)
        updateAutosaveState(for: newURL)
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
        savePendingChanges()
    }

    @MainActor func savePendingChanges(
        allowSilentRecovery: Bool = true,
        completion: (@Sendable @MainActor (Bool) -> Void)? = nil
    ) {
        guard documentState != .closed, hasUnsavedChanges else {
            completion?(true)
            return
        }

        if isAutosaving {
            autosaveQueued = true
            completion?(false)
            return
        }

        isAutosaving = true
        autosaveQueued = false
        Task { @MainActor in
            let success = await saveDocument()
            isAutosaving = false
            if success {
                fileMonitor?.markUpdated()
                saveErrorAlertIsVisible = false
            } else if !allowSilentRecovery {
                showSaveFailureAlert()
            }
            completion?(success)
            if autosaveQueued || hasUnsavedChanges {
                scheduleAutosave(after: success ? 1 : 5)
            }
        }
    }

    @MainActor private func saveDocument() async -> Bool {
        await withCheckedContinuation { continuation in
            save(to: fileURL, for: .forOverwriting) { success in
                continuation.resume(returning: success)
            }
        }
    }

    @MainActor private func scheduleAutosave(after delay: TimeInterval) {
        saveTimer?.invalidate()
        guard autosaveEnabled else {
            return
        }
        saveTimer = Timer.scheduledTimer(
            timeInterval: delay,
            target: self,
            selector: #selector(autosaveFromTimer),
            userInfo: nil,
            repeats: false
        )
    }

    @MainActor func discardPendingChanges() {
        saveTimer?.invalidate()
        saveTimer = nil
        autosaveQueued = false
        updateChangeCount(.cleared)
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

    override func autosave(completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        guard autosaveEnabled else {
            completionHandler?(true)
            return
        }
        super.autosave(completionHandler: completionHandler)
    }

    override func contents(forType _: String) throws -> Any {
        Data(sourceString.utf8)
    }

    override func close(completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        loadingProgress?.cancel()
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

private extension URL {
    var isOnNetworkVolume: Bool {
        do {
            return try resourceValues(forKeys: [.volumeIsLocalKey])
                .volumeIsLocal == false
        } catch {
            return false
        }
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
