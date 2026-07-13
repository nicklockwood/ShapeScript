//
//  DocumentBrowserViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ShapeScript
import UIKit

@MainActor
final class DocumentBrowserViewController: UIDocumentBrowserViewController,
    @MainActor UIDocumentBrowserViewControllerDelegate,
    UITextFieldDelegate
{
    private weak var rootNavigationController: UINavigationController?
    private var openingDocument = false
    private var pendingDocumentViewController: DocumentViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        allowsDocumentCreation = true
        allowsPickingMultipleItems = false

        additionalTrailingNavigationBarButtonItems = [UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelpMenu)
        )]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        if Settings.shared.showWelcomeScreenAtStartup {
            showWelcomeScreen()
        } else if appDelegate?.firstLaunchOfNewVersion ?? false {
            showWhatsNewScreen()
            appDelegate?.firstLaunchOfNewVersion = false
        }
    }

    func showWelcomeScreen() {
        let alert = UIAlertController(
            title: "Welcome to ShapeScript",
            message: """
            ShapeScript is a text-based 3D modeling tool for iOS and macOS.

            If this is your first time using ShapeScript, we recommend you check out \
            the Getting Started guide in the online documentation.

            ShapeScript is free to use for viewing and editing models in ShapeScript's \
            own shape file format.

            There is a one-time in-app purchase required to unlock the ability to \
            export ShapeScript models for use with other applications.
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "OK",
            style: .default
        ) { _ in
            Settings.shared.showWelcomeScreenAtStartup = false
        })
        present(alert, animated: true)
    }

    func showWhatsNewScreen() {
        let viewController = WhatsNewViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    func showLicensesScreen() {
        let viewController = LicensesViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    @objc func showHelpMenu() {
        let alert = UIAlertController(
            title: "ShapeScript Help",
            message: "",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "Online Documentation",
            style: .default
        ) { _ in
            UIApplication.shared.open(onlineHelpURL)
        })
        alert.addAction(UIAlertAction(
            title: "What's New in ShapeScript?",
            style: .default
        ) { [weak self] _ in
            self?.showWhatsNewScreen()
        })
        alert.addAction(UIAlertAction(
            title: "Welcome Screen",
            style: .default
        ) { [weak self] _ in
            self?.showWelcomeScreen()
        })
        alert.addAction(UIAlertAction(
            title: "Open Source Licenses",
            style: .default
        ) { [weak self] _ in
            self?.showLicensesScreen()
        })
        alert.addAction(UIAlertAction(
            title: "Examples",
            style: .default
        ) { [weak self] _ in
            self?.showExamplesMenu()
        })
        alert.addAction(UIAlertAction(
            title: "Done",
            style: .cancel
        ))
        present(alert, animated: true)
    }

    func showExamplesMenu() {
        let alert = UIAlertController(
            title: "Example Shapes",
            message: "",
            preferredStyle: .alert
        )
        if let files = Bundle.main.urls(forResourcesWithExtension: "shape", subdirectory: "Examples") {
            for url in files.sorted(by: { $0.path < $1.path }) {
                let name = url.deletingPathExtension().lastPathComponent
                alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                    self?.presentDocument(at: url)
                })
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: UIDocumentBrowserViewControllerDelegate

    func documentBrowser(
        _: UIDocumentBrowserViewController,
        didRequestDocumentCreationWithHandler importHandler: @escaping (
            URL?,
            UIDocumentBrowserViewController.ImportMode
        )
            -> Void
    ) {
        presentNewFileAlert("Untitled") { url in
            importHandler(url, .move)
        }
    }

    func documentBrowser(_: UIDocumentBrowserViewController, didPickDocumentsAt documentURLs: [URL]) {
        guard let sourceURL = documentURLs.first else { return }
        presentDocument(at: sourceURL)
    }

    func documentBrowser(
        _: UIDocumentBrowserViewController,
        didImportDocumentAt sourceURL: URL,
        toDestinationURL destinationURL: URL
    ) {
        print("importing", sourceURL, destinationURL)
        presentDocument(at: destinationURL)
    }

    func documentBrowser(
        _: UIDocumentBrowserViewController,
        failedToImportDocumentAt _: URL,
        error: Error?
    ) {
        presentError(error?.localizedDescription ?? "An unknown error occured.", onOK: {})
    }

    // MARK: Document Presentation

    var transitionController: UIDocumentBrowserTransitionController?

    func presentDocument(at documentURL: URL) {
        guard !openingDocument else { return }

        if let viewController = rootNavigationController?
            .viewControllers.first as? DocumentViewController,
            let document = viewController.document
        {
            if document.fileURL != documentURL {
                viewController.dismiss(animated: true) {
                    document.close()
                    self.rootNavigationController = nil
                    self.presentDocument(at: documentURL)
                }
            }
            return
        }

        let viewController = DocumentViewController()
        let document = Document(fileURL: documentURL)
        viewController.document = document
        viewController.loadViewIfNeeded()

        transitionController = transitionController(forDocumentAt: documentURL)
        transitionController?.targetView = viewController.scnView
        transitionController?.loadingProgress = Progress(totalUnitCount: 10)

        openingDocument = true
        pendingDocumentViewController = viewController
        document.open { [weak self] success in
            DispatchQueue.main.async { [weak self] in
                self?.finishOpeningDocument(success: success)
            }
        }
    }

    @MainActor private func finishOpeningDocument(success: Bool) {
        transitionController?.loadingProgress?.completedUnitCount = 10
        transitionController?.loadingProgress = nil
        defer {
            openingDocument = false
            pendingDocumentViewController = nil
        }
        guard success, let viewController = pendingDocumentViewController else {
            presentError("Unable to open file.", onOK: {})
            return
        }
        if let navigationController = rootNavigationController {
            navigationController.setViewControllers([viewController], animated: true)
        } else {
            let navigationController = UINavigationController(
                rootViewController: viewController
            )
            navigationController.modalPresentationStyle = .fullScreen
            rootNavigationController = navigationController
            present(navigationController, animated: true)
        }
    }

    // MARK: Document Creation

    func presentNewFileAlert(
        _ name: String,
        _ completion: @escaping (URL?) -> Void
    ) {
        let alert = UIAlertController(
            title: "New File",
            message: nil,
            preferredStyle: .alert
        )
        var textField: UITextField?
        let okAction = UIAlertAction(
            title: "OK",
            style: .default
        ) { [weak self] _ in
            var fileName = textField?.sanitizedFileName ?? ""
            guard !fileName.isEmpty else {
                completion(nil)
                return
            }
            guard !fileName.contains("/") else {
                self?.presentError(
                    "File name cannot contain / character.",
                    onOK: { self?.presentNewFileAlert(fileName, completion) }
                )
                return
            }
            guard !fileName.hasPrefix(".") else {
                self?.presentError(
                    "File name cannot begin with a . character.",
                    onOK: { self?.presentNewFileAlert(fileName, completion) }
                )
                return
            }
            var pathExtension = fileName.pathExtension
            if pathExtension.isEmpty {
                fileName += fileName.hasSuffix(".") ? "shape" : ".shape"
                pathExtension = "shape"
            } else {
                guard pathExtension.lowercased() == "shape" else {
                    self?.presentError(
                        "ShapeScript cannot open .\(fileName.pathExtension) files.",
                        onOK: { self?.presentNewFileAlert(fileName, completion) }
                    )
                    return
                }
            }
            let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(fileName)
            do {
                let data: Data = if let templateURL = Bundle.main.url(
                    forResource: "Untitled",
                    withExtension: "shape"
                ) {
                    try Data(contentsOf: templateURL)
                } else {
                    Data()
                }
                try data.write(to: fileURL, options: .atomic)
                completion(fileURL)
            } catch {
                self?.presentError(
                    error.localizedDescription,
                    onOK: { self?.presentNewFileAlert("", completion) }
                )
            }
        }
        alert.addTextField { field in
            textField = field
            field.text = name
            field.addPlaceholderExtension(".shape")
            field.returnKeyType = .done
            field.autocapitalizationType = .words
            field.autocorrectionType = .no
            field.smartDashesType = .no
            field.smartQuotesType = .no
            field.smartInsertDeleteType = .no
            field.delegate = self
            field.addAction(UIAction { [weak field] _ in
                okAction.isEnabled = field?.shouldEnableSubmit ?? false
            }, for: .editingChanged)
        }
        okAction.isEnabled = textField?.shouldEnableSubmit ?? false
        alert.addAction(okAction)
        alert.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel
        ) { _ in
            completion(nil)
        })
        present(alert, animated: true)
    }

    // MARK: UITextFieldDelegate

    func textField(_: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty {
            return true
        }
        if string.replacingOccurrences(of: "/", with: "").isEmpty {
            return false
        }
        if string.replacingOccurrences(of: ".", with: "").isEmpty,
           range.location == 0
        {
            return false
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.shouldEnableSubmit
    }

    func presentError(
        _ message: String?,
        onOK: (() -> Void)?,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        if let onOK {
            alert.addAction(UIAlertAction(
                title: "OK",
                style: .default
            ) { _ in onOK() })
        }
        if let onCancel {
            alert.addAction(UIAlertAction(
                title: "Cancel",
                style: .cancel
            ) { _ in onCancel() })
        }
        present(alert, animated: true)
    }
}

private extension UITextField {
    var shouldEnableSubmit: Bool {
        !sanitizedFileName.isEmpty
    }

    var sanitizedFileName: String {
        (text ?? "")
            .normalizingWhitespace()
            .trimmingCharacters(in: CharacterSet(charactersIn: " /"))
    }

    func addPlaceholderExtension(_ placeholder: String) {
        let placeholder = placeholder.hasPrefix(".") ?
            placeholder : ".\(placeholder)"
        let label = UILabel()
        label.alpha = 0.3
        label.isHidden = true
        label.isAccessibilityElement = false
        let container = UIView()
        container.clipsToBounds = true
        container.addSubview(label)
        addSubview(container)
        addAction(UIAction { [weak self] _ in
            guard let self else {
                return
            }
            let text = text ?? ""
            label.text = text.hasSuffix(".") ?
                String(placeholder.dropFirst()) : placeholder
            label.font = font
            container.frame = textRect(forBounds: bounds)
            label.frame = container.bounds
            if window?.contentScaleFactor == 3, UIDevice.current.systemVersion
                .compare("16", options: .numeric) == .orderedAscending
            {
                // Fix for slight baseline misalignment on @3x displays
                container.frame.origin.y -= 0.3
            }
            let size = text.size(withAttributes: defaultTextAttributes)
            label.frame.origin.x = size.width
            label.isHidden = !hasText || !text.pathExtension.isEmpty
        }, for: .editingChanged)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendActions(for: .editingChanged)
        }
    }
}

private extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }

    func normalizingWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
