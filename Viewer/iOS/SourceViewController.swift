//
//  SourceViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 19/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ShapeScript
import UIKit

let sourceActivityType = "com.charcoaldesign.ShapeScriptViewer.source"
let sourceSceneConfigurationName = "Source Configuration"
let sourceSceneTitle = "Source Editor"
private let sourceURLActivityKey = "url"

@MainActor
final class SourceViewController: UIViewController, @unchecked Sendable {
    private var undoRegistered = false
    private var undoButton: UIBarButtonItem = .init()
    private var redoButton: UIBarButtonItem = .init()
    private var saveButton: UIBarButtonItem = .init()
    private var closeButton: UIBarButtonItem?
    private var shareButton: UIBarButtonItem = .init()
    private var helpButton: UIBarButtonItem = .init()
    private var menuButton: UIBarButtonItem?
    private var textView: TokenView = .init()
    private var didNotifyDismissal = false
    private var ownsDocument = false

    var showsCloseButton = true
    var onDismiss: (() -> Void)?
    var onOpenFailure: (() -> Void)?

    var document: Document? {
        willSet { unregisterUndoManager() }
        didSet { didSetDocument() }
    }

    @objc func setOpenedDocument(_ document: Document) {
        self.document = document
    }

    func openSourceFile(_ fileURL: URL, document currentDocument: Document? = nil) {
        if fileURL == currentDocument?.documentFileURL {
            ownsDocument = false
            document = currentDocument
        } else if let document = SourceDocumentRegistry.document(for: fileURL) {
            ownsDocument = false
            self.document = document
        } else {
            Task { @MainActor in
                let document = Document(fileURL: fileURL)
                if await document.open() {
                    self.ownsDocument = true
                    self.document = document
                } else {
                    onOpenFailure?()
                }
            }
        }
    }

    override var undoManager: UndoManager? {
        document?.undoManager
    }

    override var keyCommands: [UIKeyCommand]? {
        let helpTitle = "ShapeScript Help"
        return [
            UIKeyCommand(
                title: helpTitle,
                image: nil,
                action: #selector(openHelp(_:)),
                input: "?",
                modifierFlags: .command,
                propertyList: nil,
                alternates: [],
                discoverabilityTitle: helpTitle,
                attributes: [],
                state: .off
            ),
        ]
    }

    override func loadView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        view = UIView()
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.showLineNumbers = Settings.shared.value(for: "showLineNumbers") ?? true
        textView.wrapLines = Settings.shared.value(for: "linewrapEnabled") ?? false
        textView.disableDoubleSpacePeriodShortcut = true
        textView.delegate = self

        if showsCloseButton {
            let closeButton = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in
                    self?.closeDocument()
                }
            )
            self.closeButton = closeButton
            navigationItem.leftBarButtonItem = closeButton
        }

        undoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.left"),
            menuTitle: "Undo"
        ) { [weak self] _ in
            self?.document?.undoManager?.undo()
        }
        redoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.right"),
            menuTitle: "Redo"
        ) { [weak self] _ in
            self?.document?.undoManager?.redo()
        }
        saveButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"),
            menuTitle: "Save Changes"
        ) { [weak self] _ in
            self?.saveDocument()
        }
        shareButton = UIBarButtonItem(
            systemItem: .action,
            primaryAction: UIAction { [weak self] _ in
                self?.shareSource()
            }
        )

        helpButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            menuTitle: "ShapeScript Help"
        ) { [weak self] _ in
            self?.openHelp(nil)
        }
        helpButton.accessibilityLabel = "ShapeScript Help"

        if #unavailable(iOS 16.0) {
            menuButton = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: UIMenu(children: [])
            )
            menuButton?.accessibilityLabel = "Document Actions"
        }

        didSetDocument()
        updateUndoButtons()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            notifyDismissal()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSceneTitle()
    }

    private func notifyDismissal() {
        guard !didNotifyDismissal else {
            return
        }
        didNotifyDismissal = true
        onDismiss?()
    }

    func saveDocument(completion: ((Bool) -> Void)? = nil) {
        guard let document else {
            completion?(true)
            return
        }
        document.savePendingChanges(allowSilentRecovery: false) { [weak self] success in
            self?.updateFallbackMenu()
            self?.updateUndoButtons()
            if !success, document.viewController == nil {
                self?.presentSaveFailureAlert()
            }
            completion?(success)
        }
    }

    private func presentSaveFailureAlert() {
        let alert = UIAlertController(
            title: "Error",
            message: "Failed to save changes.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "Retry",
            style: .default
        ) { [weak self] _ in
            self?.saveDocument()
        })
        alert.addAction(UIAlertAction(
            title: "Continue Without Saving",
            style: .destructive
        ) { [weak self] _ in
            self?.document?.discardPendingChanges()
            self?.updateFallbackMenu()
            self?.updateUndoButtons()
        })
        present(alert, animated: true)
    }

    func closeDocument(completion: ((Bool) -> Void)? = nil) {
        guard let document else {
            dismiss(animated: true) {
                completion?(true)
            }
            return
        }
        guard !document.autosaveEnabled, document.hasUnsavedChanges else {
            dismiss(animated: true) {
                if self.ownsDocument {
                    document.close(completionHandler: nil)
                }
                completion?(true)
            }
            return
        }

        let alert = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: "Save Changes",
            style: .default
        ) { [weak self] _ in
            self?.saveDocument { success in
                guard success else {
                    completion?(false)
                    return
                }
                self?.dismiss(animated: true) {
                    if self?.ownsDocument == true {
                        document.close(completionHandler: nil)
                    }
                    completion?(true)
                }
            }
        })
        alert.addAction(UIAlertAction(
            title: "Discard Changes",
            style: .destructive
        ) { [weak self] _ in
            document.discardPendingChanges()
            self?.dismiss(animated: true) {
                if self?.ownsDocument == true {
                    document.close(completionHandler: nil)
                }
                completion?(true)
            }
        })
        alert.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel
        ) { _ in
            completion?(false)
        })
        alert.popoverPresentationController?.barButtonItem = closeButton
        present(alert, animated: true)
    }
}

private extension SourceViewController {
    @objc func openHelp(_: Any?) {
        presentHelp(editorHelpURL)
    }

    func shareSource() {
        guard let document else {
            return
        }
        let sheet = makeShareActivityViewController(for: document)
        sheet.popoverPresentationController?.barButtonItem = shareButton
        present(sheet, animated: true)
    }

    func makeShareActivityViewController(for document: Document) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [
                UISimpleTextPrintFormatter(text: document.sourceString),
                document.documentFileURL as Any,
            ],
            applicationActivities: nil
        )
    }

    func didSetDocument() {
        updateDocumentTitle()
        userActivity = document?.documentFileURL.map(Self.userActivity(for:))
        updateSceneTitle()

        textView.text = document?.sourceString ?? ""
        textView.isEditable = document?.isEditable ?? false
        if let document {
            textView.showLineNumbers = document.showLineNumbers
            textView.wrapLines = document.linewrapEnabled
        }
        registerUndoManager()
        updateFallbackMenu()

        let documentMenuItems = document == nil ? [] : menuButton.map { [$0] } ?? []
        let shareItems: [UIBarButtonItem] = if #available(iOS 16.0, *) {
            []
        } else {
            [shareButton]
        }
        let items: [UIBarButtonItem] = if document?.isEditable ?? false {
            documentMenuItems + manualSaveItems() + [
                helpButton,
            ] + shareItems + [
                redoButton,
                undoButton,
                .flexibleSpace(),
            ]
        } else {
            documentMenuItems + [
                helpButton,
            ] + shareItems + [
                .flexibleSpace(),
            ]
        }
        setRightBarButtonItems(items, animated: isViewLoaded)
    }

    func updateFallbackMenu() {
        guard let menuButton else {
            return
        }
        menuButton.isEnabled = document != nil
        var children: [UIMenuElement] = [
            UIAction(
                title: "Duplicate",
                image: UIImage(systemName: "plus.square.on.square")
            ) { [weak self] _ in
                self?.duplicate(nil)
            },
        ]
        if document?.isEditable == true {
            children.append(UIAction(
                title: "Move",
                image: UIImage(systemName: "folder")
            ) { [weak self] _ in
                self?.move(nil)
            })
            if let saveMenu = buildSaveMenu() {
                children.insert(saveMenu, at: 0)
            }
        }
        if let document {
            children.insert(buildEditorSettingsMenu(for: document), at: 0)
        }
        if let findMenu = document.flatMap(buildFindMenu(for:)) {
            children.insert(findMenu, at: 0)
        }
        menuButton.menu = UIMenu(children: children)
    }

    func setRightBarButtonItems(_ items: [UIBarButtonItem], animated: Bool) {
        let currentItems = navigationItem.rightBarButtonItems ?? []
        guard currentItems.count != items.count ||
            !zip(currentItems, items).allSatisfy({ $0 === $1 })
        else {
            return
        }
        navigationItem.setRightBarButtonItems(items, animated: animated)
    }

    var documentTitle: String? {
        document?.documentFileURL?.displayName
    }

    func updateDocumentTitle() {
        title = documentTitle
        if #available(iOS 16.0, *) {
            navigationItem.configureDocumentTitleMenu(
                fileURL: document?.documentFileURL,
                renameDelegate: document == nil ? nil : self,
                activityViewControllerProvider: document.map { document in
                    { [weak self] in
                        self?.makeShareActivityViewController(for: document) ??
                            UIActivityViewController(
                                activityItems: [document.documentFileURL as Any],
                                applicationActivities: nil
                            )
                    }
                },
                menuProvider: document.map { document in
                    { [weak self] suggestedActions in
                        guard let self else {
                            return suggestedActions
                        }
                        return [
                            buildEditorSettingsMenu(for: document),
                            buildFindMenu(for: document),
                            UIMenu(options: .displayInline, children: suggestedActions),
                        ].compactMap { $0 }
                    }
                }
            )
        }
    }

    func updateSceneTitle() {
        guard view.window?.windowScene?.session.configuration.name == sourceSceneConfigurationName else {
            return
        }
        view.window?.windowScene?.title = sourceSceneTitle
    }

    func unregisterUndoManager() {
        undoRegistered = false
        document?.undoManager = nil
        NotificationCenter.default.removeObserver(
            self,
            name: .NSUndoManagerCheckpoint,
            object: nil
        )
    }

    func registerUndoManager() {
        guard !undoRegistered, let document else { return }
        undoRegistered = true
        document.undoManager = textView.undoManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateUndoButtons),
            name: .NSUndoManagerCheckpoint,
            object: document.undoManager
        )
    }

    @objc func updateUndoButtons() {
        undoButton.setEnabled(document?.undoManager.canUndo == true)
        redoButton.setEnabled(document?.undoManager.canRedo == true)
        updateSaveButton()
    }

    func manualSaveItems() -> [UIBarButtonItem] {
        guard document?.autosaveEnabled == false else {
            return []
        }
        updateSaveButton()
        return [saveButton]
    }

    func updateSaveButton() {
        saveButton.setEnabled(
            document?.autosaveEnabled == false &&
                document?.hasUnsavedChanges == true
        )
    }

    func buildSaveMenu() -> UIMenu? {
        guard document?.autosaveEnabled == false else {
            return nil
        }
        let action = UIAction(
            title: "Save Changes",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            self?.saveDocument()
        }
        action.attributes = document?.hasUnsavedChanges == true ? [] : .disabled
        return UIMenu(options: .displayInline, children: [action])
    }

    func buildFindMenu(for document: Document) -> UIMenu? {
        guard #available(iOS 16.0, *) else {
            return nil
        }
        return UIMenu(options: .displayInline, children: [
            UIAction(
                title: document.isEditable ? "Find and Replace" : "Find",
                image: UIImage(systemName: "text.magnifyingglass")
            ) { [weak self] _ in
                self?.textView.findInteraction?.presentFindNavigator(showingReplace: true)
            },
        ])
    }

    func buildEditorSettingsMenu(for document: Document) -> UIMenu {
        UIMenu(options: .displayInline, children: [
            UIAction(
                title: "Line Numbers",
                image: UIImage(systemName: "list.number"),
                state: document.showLineNumbers ? .on : .off
            ) { [weak self] _ in
                document.showLineNumbers.toggle()
                self?.textView.showLineNumbers = document.showLineNumbers
                self?.updateDocumentTitle()
                self?.updateFallbackMenu()
            },
            UIAction(
                title: "Wrap Lines",
                image: UIImage(systemName: "arrow.turn.down.left"),
                state: document.linewrapEnabled ? .on : .off
            ) { [weak self] _ in
                document.linewrapEnabled.toggle()
                self?.textView.wrapLines = document.linewrapEnabled
                self?.updateDocumentTitle()
                self?.updateFallbackMenu()
            },
        ])
    }
}

extension SourceViewController {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(duplicate(_:)):
            document != nil
        case #selector(move(_:)):
            document?.isEditable == true
        default:
            super.canPerformAction(action, withSender: sender)
        }
    }

    override func duplicate(_: Any?) {
        guard let fileURL = document?.documentFileURL else {
            return
        }
        present(UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true), animated: true)
    }

    override func move(_: Any?) {
        guard document?.isEditable == true, let fileURL = document?.documentFileURL else {
            return
        }
        present(UIDocumentPickerViewController(forExporting: [fileURL]), animated: true)
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        guard let fileURL = document?.documentFileURL else {
            return
        }
        activity.addUserInfoEntries(from: [
            sourceURLActivityKey: fileURL.absoluteString,
        ])
    }

    static func userActivity(for fileURL: URL) -> NSUserActivity {
        let activity = NSUserActivity(activityType: sourceActivityType)
        activity.title = fileURL.displayName
        activity.targetContentIdentifier = fileURL.absoluteString
        activity.userInfo = [sourceURLActivityKey: fileURL.absoluteString]
        return activity
    }

    static func fileURL(from activity: NSUserActivity?) -> URL? {
        guard let string = activity?.userInfo?[sourceURLActivityKey] as? String else {
            return nil
        }
        return URL(string: string)
    }
}

@available(iOS 16.0, *)
extension SourceViewController: UINavigationItemRenameDelegate {
    func navigationItemShouldBeginRenaming(_: UINavigationItem) -> Bool {
        document?.isEditable == true
    }

    func navigationItem(
        _: UINavigationItem,
        willBeginRenamingWith suggestedTitle: String,
        selectedRange _: Range<String.Index>
    ) -> (String, Range<String.Index>) {
        guard let fileURL = document?.fileURL else {
            return (suggestedTitle, suggestedTitle.startIndex ..< suggestedTitle.endIndex)
        }
        let title = fileURL.displayBaseName
        return (title, title.startIndex ..< title.endIndex)
    }

    func navigationItem(_: UINavigationItem, shouldEndRenamingWith title: String) -> Bool {
        document?.proposedName(for: title) != nil
    }

    func navigationItem(_: UINavigationItem, didEndRenamingWith title: String) {
        guard let document, let proposedName = document.proposedName(for: title) else {
            updateDocumentTitle()
            updateSceneTitle()
            return
        }

        document.renameAndRefresh(
            proposedName: proposedName
        ) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                break
            case let .failure(error):
                updateDocumentTitle()
                updateSceneTitle()
                presentRenameError(error)
            }
        }
    }

    private func presentRenameError(_ error: any Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

@MainActor
enum SourceDocumentRegistry {
    private final class Entry {
        weak var document: Document?

        init(document: Document) {
            self.document = document
        }
    }

    private static var documents = [URL: Entry]()

    static func register(_ document: Document, for fileURL: URL) {
        documents = documents.filter { $0.value.document !== document }
        documents[fileURL.standardizedFileURL] = Entry(document: document)
    }

    static func document(for fileURL: URL) -> Document? {
        documents[fileURL.standardizedFileURL]?.document
    }
}

@MainActor
@objc(SourceSceneDelegate)
final class SourceSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        windowScene.title = sourceSceneTitle

        let activity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
        guard let fileURL = SourceViewController.fileURL(from: activity) else {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            return
        }

        let viewController = SourceViewController()
        viewController.showsCloseButton = false
        viewController.onOpenFailure = {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
        }
        viewController.openSourceFile(fileURL)

        let navigationController = UINavigationController(rootViewController: viewController)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        self.window = window
    }

    func stateRestorationActivity(for _: UIScene) -> NSUserActivity? {
        sourceViewController?.userActivity
    }

    func load(_ fileURL: URL, document currentDocument: Document? = nil) {
        sourceViewController?.openSourceFile(fileURL, document: currentDocument)
    }

    var sourceViewController: SourceViewController? {
        (window?.rootViewController as? UINavigationController)?
            .viewControllers.first as? SourceViewController
    }
}

extension UIApplication {
    func closeSourceScenes() {
        Task { @MainActor in
            let sourceSessions = self.openSessions.filter {
                $0.configuration.name == sourceSceneConfigurationName
            }
            for session in sourceSessions {
                self.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            }
        }
    }
}

extension TokenView.TokenType {
    static let comment = Self(rawValue: "comment")
    static let `operator` = Self(rawValue: "operator")
    static let identifier = Self(rawValue: "identifier")
    static let keyword = Self(rawValue: "keyword")
    static let string = Self(rawValue: "string")
    static let number = Self(rawValue: "number")
    static let color = Self(rawValue: "color")
    static let member = Self(rawValue: "member")
    static let stdlib = Self(rawValue: "stdlib")
}

extension TokenType {
    var tokenViewType: TokenView.TokenType {
        switch self {
        case .dot, .prefix, .infix, .lbrace, .rbrace, .lparen, .rparen, .call, .lbracket, .rbracket, .subscript:
            .operator
        case .identifier:
            .identifier
        case .keyword:
            .keyword
        case .hexColor:
            .color
        case .number:
            .number
        case .string:
            .string
        case .comment:
            .comment
        case .linebreak, .eof:
            .identifier
        }
    }
}

extension Token {
    var tokenViewToken: TokenView.Token {
        .init(
            type: type.tokenViewType,
            range: range
        )
    }
}

extension SourceViewController: TokenViewDelegate {
    func tokens(for input: String) -> [TokenView.Token] {
        var stack = [Set<String>()]
        var isSwitch = [false]
        var lastKeyword: String?
        var lastToken: ShapeScript.Token?
        return (try? tokenize(input).map { token -> TokenView.Token in
            if case .comment = token.type {
                return token.tokenViewToken
            }
            defer { lastToken = token }
            var viewToken = token.tokenViewToken
            switch token.type {
            case .lbrace:
                stack.append(stack.last!)
                isSwitch.append(lastKeyword == "switch")
            case .rbrace where stack.count > 1:
                stack.removeLast()
                isSwitch.removeLast()
            case .linebreak, .eof:
                lastKeyword = nil
            case let .keyword(name):
                lastKeyword = name.rawValue
            case let .identifier(name):
                if lastKeyword == "option",
                   case .identifier("option")? = lastToken?.type
                {
                    stack[stack.count - 1].insert(name)
                    lastKeyword = nil
                    break
                }
                if isSwitch.last == true, name == "case" {
                    viewToken.type = .keyword
                    break
                }
                if case .keyword(.define)? = lastToken?.type {
                    stack[stack.count - 1].insert(name)
                    lastKeyword = nil
                    break
                } else if case .dot = lastToken?.type {
                    viewToken.type = .member
                    break
                }
                if stack.last!.contains(name) {
                    break
                }
                switch name {
                case "in", "to", "step", "option", "not", "true", "false", "switch":
                    // contextual keywords
                    viewToken.type = .keyword
                    lastKeyword = name
                case _ where ShapeScript.stdlibSymbols.contains(name):
                    viewToken.type = .stdlib
                default:
                    break
                }
            default:
                break
            }
            return viewToken
        }) ?? []
    }

    func attributes(for tokenType: TokenView.TokenType) -> [NSAttributedString.Key: Any] {
        switch tokenType {
        case .keyword:
            [.foregroundColor: UIColor.systemPurple]
        case .number:
            [.foregroundColor: UIColor.orange]
        case .string, .color:
            [.foregroundColor: UIColor.systemRed]
        case .stdlib, .member:
            [.foregroundColor: UIColor {
                $0.userInterfaceStyle == .dark ? .systemTeal : .systemIndigo
            }]
        case .comment:
            [.foregroundColor: UIColor.systemGray]
        case .identifier, .operator, _:
            [:]
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        document?.sourceString = textView.text
        document?.scheduleAutosave()
        document?.fileMonitor?.markUpdated()
        if undoManager?.isUndoing ?? false {
            document?.updateChangeCount(.undone)
        } else if undoManager?.isRedoing ?? false {
            document?.updateChangeCount(.redone)
        } else {
            document?.updateChangeCount(.done)
        }
        updateSaveButton()
        updateFallbackMenu()
    }
}

extension SourceViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let navigationBar = navigationController?.navigationBar
        let underMenu = scrollView.contentOffset.y > -view.safeAreaInsets.top
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            if underMenu {
                appearance.configureWithDefaultBackground()
            } else {
                appearance.configureWithTransparentBackground()
            }
            navigationBar?.scrollEdgeAppearance = appearance
        } else if underMenu {
            navigationBar?.standardAppearance.configureWithDefaultBackground()
        } else {
            navigationBar?.standardAppearance.configureWithTransparentBackground()
        }
    }
}
