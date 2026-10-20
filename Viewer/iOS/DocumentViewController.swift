//
//  DocumentViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ContextMenu
import Euclid
import SceneKit
import ShapeScript
import SwiftUI
import UIKit

final class WarningTextView: UITextView, UIGestureRecognizerDelegate {
    var onNext: (@MainActor () -> Void)?
    private var hadSelection = false
    private lazy var advanceTap = UITapGestureRecognizer(target: self, action: #selector(advanceWarning))

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        advanceTap.cancelsTouchesInView = false
        advanceTap.delegate = self
        addGestureRecognizer(advanceTap)

        // Let a double tap select a word before deciding whether a single tap should advance.
        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        advanceTap.require(toFail: doubleTap)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive _: UITouch) -> Bool {
        if gestureRecognizer === advanceTap {
            hadSelection = selectedRange.length > 0
        }
        return true
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func advanceWarning() {
        if hadSelection {
            selectedRange = NSRange(location: selectedRange.location, length: 0)
        } else if selectedRange.length == 0 {
            onNext?()
        }
    }
}

@MainActor
protocol ExportMenuProvider {
    func updateExportMenu()
}

@MainActor
final class DocumentViewController: UIViewController, DocumentViewControllerProtocol,
    UIAdaptivePresentationControllerDelegate
{
    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var scnView: SCNView = .init()
    private let consoleViewController: ConsoleViewController = .init()
    private var isPreparingModalPresentation = false
    private let renderProgressView: ProgressView = .init()
    private let containerView: SplitView = .init()
    private(set) var exportButton: UIBarButtonItem = .init()
    private weak var warningView: UIView?
    var warningPresentation: WarningQueue.Presentation?
    private var warningNextHandler: (@MainActor @Sendable () -> Void)?
    private var warningDismissHandler: (@MainActor @Sendable () -> Void)?
    private var compactWarningConstraints = [NSLayoutConstraint]()
    private var regularWarningConstraints = [NSLayoutConstraint]()
    #if os(visionOS)
    private var consoleOrnament: UIHostingOrnament<ConsoleOrnamentContainer>?
    #endif

    let errorTextView: UITextView = .init()
    let grantAccessButton: UIButton = .init(type: .system)

    private var closeButton: UIBarButtonItem = .init()
    private var loadingItem: UIBarButtonItem = .init()
    private var infoButton: UIBarButtonItem = .init()
    private var cameraButton: UIBarButtonItem = .init()
    private var editButton: UIBarButtonItem = .init()

    var document: Document? {
        didSet {
            document?.viewController = self
            updateEditButton()
            document?.rerender()
        }
    }

    /// In preview mode, document view is non-editable. Used for QuickLook
    var isQuickLook: Bool = false

    lazy var cameraNode: SCNNode = makeCameraNode()

    weak var axesNode: SCNNode?

    var navigationBar: UINavigationBar? {
        navigationController?.navigationBar
    }

    var errorMessage: NSAttributedString? {
        didSet {
            errorLayoutWidth = nil
            guard errorMessage != nil else {
                errorTextView.isHidden = true
                navigationBar?.tintColor = interfaceColor
                cameraButton.isEnabled = true
                exportButton.isEnabled = true
                return
            }
            layoutErrorMessage()
            errorTextView.isHidden = false
            navigationBar?.tintColor = .white
            cameraButton.isEnabled = false
            exportButton.isEnabled = false
        }
    }

    private var errorLayoutWidth: CGFloat?

    private func layoutErrorMessage() {
        guard let errorMessage else { return }
        let insets = errorTextView.textContainerInset
        let width = errorTextView.bounds.width - insets.left - insets.right -
            2 * errorTextView.textContainer.lineFragmentPadding
        guard width > 0, errorLayoutWidth != width else { return }
        errorLayoutWidth = width
        errorTextView.attributedText = errorMessage.wrappingErrorExcerpt(toWidth: width)
    }

    var hasLog: Bool { consoleViewController.hasLog }

    func clearLog() {
        consoleViewController.clearLog()
    }

    func appendLog(_ text: String) {
        consoleViewController.appendLog(text)
        DispatchQueue.main.async {
            self.presentConsole()
            #if os(visionOS)
            self.updateConsoleOrnament()
            #else
            if self.consoleViewController.consoleView.superview === self.containerView,
               self.containerView.heights.count > 1
            {
                self.containerView.heights[1] =
                    self.consoleViewController.inlineHeight(maximumHeight: 150)
            }
            #endif
        }
    }

    func updateModals() {
        guard let viewController = presentedSourceViewController(),
              let fileURL = viewController.document?.fileURL
        else {
            return
        }

        openSourceFile(fileURL, in: viewController)
    }

    var isLoading = false {
        didSet {
            guard isLoading != oldValue else {
                return
            }
            if !isLoading {
                refreshView()
            }
            updateRenderProgressView()
        }
    }

    var renderProgress: Double? {
        didSet {
            updateRenderProgressView()
        }
    }

    private func updateRenderProgressView() {
        renderProgressView.progress = renderProgress
        renderProgressView.isActive = isLoading || renderProgress != nil
        updateLoadingButton()
    }

    var showConsole = false {
        didSet {
            guard showConsole != oldValue else {
                return
            }
            if showConsole {
                presentConsole()
            } else {
                dismissConsole()
            }
        }
    }

    var showAxes = false {
        didSet {
            if showAxes != oldValue {
                refreshAxesAndCamera()
            }
        }
    }

    var isOrthographic = false {
        didSet {
            if isOrthographic != oldValue {
                refreshOrthographic()
            }
        }
    }

    var camera: Camera = .default {
        didSet {
            if camera != oldValue {
                refreshAxesAndCamera()
                resetView()
            }
        }
    }

    var background: MaterialProperty? {
        get { MaterialProperty(scnScene.background) }
        set {
            if newValue != background {
                newValue?.configureProperty(scnScene.background)
                updateInterfaceColor()
            }
        }
    }

    var exportMenuProvider: ExportMenuProvider? {
        self as Any as? ExportMenuProvider
    }

    func updateInterfaceColor() {
        navigationBar?.tintColor = errorMessage.map { _ in .white } ?? interfaceColor
        renderProgressView.color = interfaceColor
        grantAccessButton.tintColor = .white
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        #endif
    }

    func updateEditButton() {
        let isEditable = document?.isEditable ?? false
        editButton.image = UIImage(systemName: isEditable ? "square.and.pencil" : "doc.plaintext")
        let title = isEditable ? "Open in Editor" : "View Source"
        editButton.accessibilityLabel = title
        if #available(iOS 16.0, *) {
            editButton.menuRepresentation = UIAction(
                title: title,
                image: editButton.image
            ) { [weak self] _ in
                self?.openSourceEditor()
            }
        }
    }

    func updateSceneTitle() {
        view.window?.windowScene?.title = document?.fileURL.displayBaseName ?? mainSceneTitle
    }

    func updateNavigationButtons(animated: Bool = true) {
        let items = exportMenuProvider == nil ?
            [cameraButton, infoButton, editButton] :
            [exportButton, cameraButton, infoButton, editButton]
        setRightBarButtonItems(items, animated: animated)
    }

    func updateLoadingButton(animated: Bool = true) {
        guard loadingItem.customView != nil else {
            return
        }
        let items = isLoading || renderProgress != nil ? [closeButton, loadingItem] : [closeButton]
        let currentItems = navigationItem.leftBarButtonItems ?? []
        guard currentItems.count != items.count ||
            !zip(currentItems, items).allSatisfy({ $0 === $1 })
        else {
            return
        }
        navigationItem.setLeftBarButtonItems(items, animated: animated)
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

    override var preferredStatusBarStyle: UIStatusBarStyle {
        isBrightBackground ? .darkContent : .lightContent
    }

    func didRefreshScene() {
        rebuildMenu()
    }

    func didRefreshCamera() {
        rebuildMenu()
    }

    func didRefreshOrthographic() {
        rebuildMenu()
    }

    func didResetView() {
        rebuildMenu()
    }

    weak var selectedGeometry: Geometry?

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(containerView)

        errorTextView.translatesAutoresizingMaskIntoConstraints = false
        errorTextView.isEditable = false
        errorTextView.backgroundColor = UIColor(
            red: 0.863,
            green: 0.129,
            blue: 0.008,
            alpha: 0.8
        )
        errorTextView.isHidden = true
        rootView.addSubview(errorTextView)

        grantAccessButton.translatesAutoresizingMaskIntoConstraints = false
        grantAccessButton.setTitle("Grant Access", for: .normal)
        grantAccessButton.addTarget(self, action: #selector(grantAccess), for: .touchUpInside)
        rootView.addSubview(grantAccessButton)

        closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(dismissDocumentViewController)
        )
        exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: nil,
            action: nil
        )
        cameraButton = UIBarButtonItem(
            image: UIImage(systemName: "camera"),
            style: .plain,
            target: nil,
            action: nil
        )
        infoButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            menuTitle: "Scene Info"
        ) { [weak self] _ in
            self?.showModelInfo()
        }
        editButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(openSourceEditor)
        )
        navigationItem.leftBarButtonItem = closeButton
        updateNavigationButtons(animated: false)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            errorTextView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            errorTextView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            errorTextView.topAnchor.constraint(equalTo: rootView.topAnchor),
            errorTextView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            grantAccessButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            grantAccessButton.bottomAnchor.constraint(
                equalTo: rootView.safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            ),
        ])

        view = rootView
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateWarningLayoutConstraints()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        errorTextView.textContainerInset = UIEdgeInsets(
            top: view.safeAreaInsets.top + 60,
            left: max(view.safeAreaInsets.left + 15, 20),
            bottom: view.safeAreaInsets.bottom + 20,
            right: max(view.safeAreaInsets.right + 15, 20)
        )
        layoutErrorMessage()
        updateInterfaceColor()
        if !cameraHasMoved {
            refreshAxesAndCamera()
            resetView()
        }
        #if os(visionOS)
        updateConsoleOrnament()
        #endif
        rebuildMenu()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // create view
        scnView = SCNView(frame: containerView.bounds, options: [:])
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addArrangedSubview(scnView, height: nil)

        // set the scene to the view
        scnView.scene = scnScene

        // configure navigation bar
        renderProgressView.frame = CGRect(origin: .zero, size: renderProgressView.intrinsicContentSize)
        loadingItem = UIBarButtonItem(customView: renderProgressView)
        updateLoadingButton(animated: false)
        navigationBar?.standardAppearance.configureWithTransparentBackground()
        if let exportMenuProvider {
            exportMenuProvider.updateExportMenu()
        } else {
            updateNavigationButtons(animated: false)
        }

        // configure the view
        containerView.backgroundColor = backgroundColor
        scnView.backgroundColor = .clear // Important!
        scnView.isOpaque = false
        scnView.defaultCameraController.delegate = self
        scnView.pointOfView = cameraNode
        updateInterfaceColor()
        updateEditButton()
        document?.updateViews()
        refreshScene()

        // configure camera menu
        rebuildMenu()

        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        scnView.addInteraction(ContextMenuInteraction { [weak self] location in
            guard let self,
                  let menu = selectionMenu(at: location)
            else {
                return nil
            }
            let style: ContextMenuInteraction.Configuration.PresentationStyle =
                selectableGeometries(at: location).count == 1 ? .editMenu : .automatic
            return ContextMenuInteraction.Configuration(
                menu: menu,
                presentationStyle: style
            )
        })

        // add a tap gesture to error view
        let tapGesture2 = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        errorTextView.addGestureRecognizer(tapGesture2)

        if self as Any is ExportMenuProvider {
            scheduleCameraMovedTimer()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSceneTitle()
        checkDocumentWarnings()
        if showConsole {
            presentConsole()
        }
    }

    @discardableResult
    func presentError(_ error: any Error, completionHandler: (() -> Void)? = nil) -> Bool {
        let alert = UIAlertController(
            title: "Warning",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "OK",
            style: .default
        ) { [weak self, weak alert] _ in
            completionHandler?()
            self?.restoreConsoleWhenDismissed(alert)
        })
        presentModalHidingConsole(alert)
        return true
    }

    func showWarning(
        _ message: NSAttributedString,
        onNext: @escaping @MainActor @Sendable () -> Void,
        onDismissAll: @escaping @MainActor @Sendable () -> Void
    ) {
        dismissWarning(notify: false)
        warningNextHandler = onNext
        warningDismissHandler = onDismissAll

        let banner = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.clipsToBounds = true
        banner.layer.cornerRadius = 18
        banner.layer.cornerCurve = .continuous

        let tintView = UIView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.5)
        banner.contentView.addSubview(tintView)

        let imageView = UIImageView(
            image: UIImage(systemName: "exclamationmark.triangle.fill")
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit

        let label = WarningTextView(frame: .zero, textContainer: nil)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = message
        label.textColor = .label
        label.backgroundColor = .clear
        label.isEditable = false
        label.isSelectable = true
        label.isScrollEnabled = false
        label.textContainerInset = .zero
        label.textContainer.lineFragmentPadding = 0
        label.onNext = { [weak self] in self?.nextWarningPressed() }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let nextButton = UIButton(type: .custom)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.accessibilityLabel = "Next warning"
        nextButton.accessibilityHint = "Show the next warning"
        nextButton.addTarget(self, action: #selector(nextWarningPressed), for: .touchUpInside)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Dismiss all warnings"
        closeButton.addTarget(
            self,
            action: #selector(dismissWarningPressed),
            for: .touchUpInside
        )

        banner.contentView.addSubview(imageView)
        banner.contentView.addSubview(nextButton)
        // Selection gestures belong to the text view, not the next-warning button beneath it.
        banner.contentView.addSubview(label)
        banner.contentView.addSubview(closeButton)
        view.addSubview(banner)
        warningView = banner
        compactWarningConstraints = [
            banner.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            banner.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
        ]
        let preferredWidth = banner.widthAnchor.constraint(equalToConstant: 640)
        preferredWidth.priority = .defaultHigh
        regularWarningConstraints = [
            preferredWidth,
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            banner.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ]

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: banner.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: banner.contentView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: banner.contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: banner.contentView.bottomAnchor),

            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            imageView.leadingAnchor.constraint(equalTo: banner.contentView.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: banner.contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 9),
            label.topAnchor.constraint(equalTo: banner.contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: banner.contentView.bottomAnchor, constant: -12),

            nextButton.leadingAnchor.constraint(equalTo: banner.contentView.leadingAnchor),
            nextButton.topAnchor.constraint(equalTo: banner.contentView.topAnchor),
            nextButton.bottomAnchor.constraint(equalTo: banner.contentView.bottomAnchor),
            nextButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),

            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: banner.contentView.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: banner.contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        updateWarningLayoutConstraints()
    }

    @objc private func dismissWarningPressed() {
        dismissWarning(notify: true)
    }

    @objc private func nextWarningPressed() {
        warningDismissHandler = warningNextHandler
        dismissWarning(notify: true)
    }

    func hideWarning() {
        dismissWarning(notify: false)
    }

    private func dismissWarning(notify: Bool) {
        warningNextHandler = nil
        guard let warningView else {
            if notify, let handler = warningDismissHandler {
                warningDismissHandler = nil
                handler()
            } else if !notify {
                warningDismissHandler = nil
            }
            return
        }
        self.warningView = nil
        guard notify, let handler = warningDismissHandler else {
            NSLayoutConstraint.deactivate(compactWarningConstraints + regularWarningConstraints)
            warningView.removeFromSuperview()
            compactWarningConstraints.removeAll()
            regularWarningConstraints.removeAll()
            if !notify {
                warningDismissHandler = nil
            }
            return
        }
        warningDismissHandler = nil
        let constraints = compactWarningConstraints + regularWarningConstraints
        compactWarningConstraints.removeAll()
        regularWarningConstraints.removeAll()
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            warningView.alpha = 0
            warningView.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            NSLayoutConstraint.deactivate(constraints)
            warningView.removeFromSuperview()
            handler()
        }
    }

    private func updateWarningLayoutConstraints() {
        let isCompact = traitCollection.horizontalSizeClass == .compact
        NSLayoutConstraint.deactivate(isCompact ? regularWarningConstraints : compactWarningConstraints)
        NSLayoutConstraint.activate(isCompact ? compactWarningConstraints : regularWarningConstraints)
    }

    private func presentConsole() {
        #if os(visionOS)
        presentOrnamentConsole()
        #else
        if #available(iOS 16, *) {
            presentSheetConsole()
        } else {
            presentInlineConsole()
        }
        #endif
    }

    #if os(visionOS)

    private func presentOrnamentConsole() {
        guard view.window != nil else {
            return
        }
        if consoleOrnament == nil {
            let ornament = UIHostingOrnament(sceneAnchor: .bottom) {
                consoleOrnamentView
            }
            ornaments.append(ornament)
            consoleOrnament = ornament
        } else {
            updateConsoleOrnament()
        }
    }

    #endif

    @available(iOS 16, *)
    private func presentSheetConsole() {
        guard view.window != nil,
              consoleViewController.presentingViewController == nil
        else {
            return
        }
        guard presentedViewController == nil else {
            restoreConsoleWhenDismissed(nil)
            return
        }

        consoleViewController.configureSheetPresentation(delegate: self)
        present(consoleViewController, animated: true) { [consoleViewController] in
            consoleViewController.didPresentAsSheet()
        }
    }

    private func dismissConsole() {
        #if os(visionOS)
        dismissOrnamentConsole()
        #else
        dismissSheetConsole(restoreIfNeeded: true)
        #endif
    }

    #if os(visionOS)

    private func dismissOrnamentConsole() {
        guard let consoleOrnament else {
            return
        }
        ornaments.removeAll { $0 === consoleOrnament }
        self.consoleOrnament = nil
    }

    private func updateConsoleOrnament() {
        consoleOrnament?.rootView = consoleOrnamentView
    }

    private var consoleOrnamentView: ConsoleOrnamentContainer {
        ConsoleOrnamentContainer(
            viewController: consoleViewController,
            size: CGSize(
                width: consoleOrnamentWidth,
                height: consoleOrnamentHeight
            )
        )
    }

    private var consoleOrnamentWidth: CGFloat {
        let windowWidth = max(view.bounds.width, 320)
        return max(windowWidth - 120, 280)
    }

    private var consoleOrnamentHeight: CGFloat {
        consoleViewController.preferredHeight(maximumHeight: 150)
    }

    #endif

    private func dismissSheetConsole(
        animated: Bool = true,
        restoreIfNeeded: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard consoleViewController.presentingViewController != nil else {
            completion?()
            return
        }
        consoleViewController.preserveDetent()
        consoleViewController.dismiss(animated: animated) { [weak self] in
            completion?()
            if restoreIfNeeded, self?.showConsole == true {
                self?.presentConsole()
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === consoleViewController {
            consoleViewController.preserveDetent()
            showConsole = false
            return
        }
        restoreConsoleAfterModalIfNeeded()
    }

    private func presentInlineConsole() {
        guard consoleViewController.consoleView.superview == nil else {
            return
        }
        addChild(consoleViewController)
        consoleViewController.consoleView.frame.size.width = scnView.frame.width
        consoleViewController.consoleView.sizeToFit()
        let height = consoleViewController.consoleView.frame.height +
            view.safeAreaInsets.bottom
        containerView.addArrangedSubview(
            consoleViewController.consoleView,
            height: height
        )
        consoleViewController.didMove(toParent: self)
    }

    private func restoreConsoleAfterModalIfNeeded() {
        guard showConsole,
              !isPreparingModalPresentation,
              presentedViewController == nil
        else {
            return
        }
        presentConsole()
    }

    func restoreConsoleWhenDismissed(_: UIViewController?, remainingAttempts: Int = 40) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if presentedViewController == nil {
                restoreConsoleAfterModalIfNeeded()
            } else if remainingAttempts > 0 {
                restoreConsoleWhenDismissed(
                    nil,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }

    func presentModalHidingConsole(
        _ viewController: UIViewController,
        animated: Bool = true,
        preparation: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        isPreparingModalPresentation = true
        let usesPresentationDelegate = (viewController as? UIAlertController)?
            .preferredStyle != .alert

        let presentModal = { [weak self] in
            guard let self else { return }
            if usesPresentationDelegate {
                viewController.presentationController?.delegate = self
            }
            present(viewController, animated: animated) { [weak self] in
                if usesPresentationDelegate {
                    viewController.presentationController?.delegate = self
                }
                self?.isPreparingModalPresentation = false
                completion?()
            }
            preparation?()
        }

        guard let presentedViewController else {
            presentModal()
            return
        }

        if presentedViewController === consoleViewController {
            dismissSheetConsole(animated: animated, completion: presentModal)
        } else if let sourceViewController = presentedSourceViewController() {
            sourceViewController.present(viewController, animated: animated) { [weak self] in
                self?.isPreparingModalPresentation = false
                completion?()
            }
            preparation?()
        } else {
            presentedViewController.dismiss(animated: animated, completion: presentModal)
        }
    }

    private func presentedSourceViewController() -> SourceViewController? {
        var viewController = presentedViewController
        while let current = viewController {
            if let navController = current as? UINavigationController,
               let sourceViewController = navController.viewControllers
                   .first(where: { $0 is SourceViewController }) as? SourceViewController
            {
                return sourceViewController
            }
            if let sourceViewController = current as? SourceViewController {
                return sourceViewController
            }
            viewController = current.presentedViewController
        }
        return nil
    }

    private var _cameraHadMoved = false
    private func scheduleCameraMovedTimer() {
        Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(cameraMovedTimerFired),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func cameraMovedTimerFired() {
        if cameraHasMoved != _cameraHadMoved {
            _cameraHadMoved = cameraHasMoved
            rebuildMenu()
        }
        scheduleCameraMovedTimer()
    }

    private func rebuildMenu() {
        // Update camera menu
        let cameras: [Camera] = if let document {
            document.cameras
        } else {
            CameraType.allCases.map {
                Camera(type: $0)
            } + (0 ..< 9 - CameraType.allCases.count).map {
                Camera(type: CameraType(rawValue: "custom\($0)"))
            }
        }
        var cameraItems = [UIMenuElement]()
        for (i, camera) in cameras.enumerated() {
            let item = UIAction(
                title: camera.name,
                image: nil,
                identifier: nil,
                discoverabilityTitle: nil,
                attributes: [],
                state: self.camera == camera ?
                    (cameraHasMoved ? .mixed : .on) : .off
            ) { [weak self] _ in
                _ = self?.document?.selectCamera(at: i)
            }
            cameraItems.append(item)
        }
        let cameraMenu = UIMenu(
            title: "",
            image: nil,
            identifier: nil,
            options: [],
            children: [
                UIAction(
                    title: "Reset View",
                    image: nil,
                    identifier: nil,
                    discoverabilityTitle: nil,
                    attributes: cameraHasMoved ? [] : .disabled,
                    state: .off
                ) { [weak self] _ in
                    self?.resetCamera()
                },
                UIMenu(
                    title: "",
                    image: nil,
                    identifier: nil,
                    options: .displayInline,
                    children: cameraItems
                ),
                UIMenu(
                    title: "",
                    image: nil,
                    identifier: nil,
                    options: .displayInline,
                    children: [
                        UIAction(
                            title: "Orthographic",
                            image: nil,
                            identifier: nil,
                            discoverabilityTitle: nil,
                            attributes: camera.isOrthographic.map { _ in .disabled } ?? [],
                            state: camera.isOrthographic ?? isOrthographic ? .on : .off
                        ) { [weak self] _ in
                            self?.toggleOrthographic()
                        },
                        UIAction(
                            title: "Show Wireframe",
                            image: nil,
                            identifier: nil,
                            discoverabilityTitle: nil,
                            attributes: [],
                            state: document?.showWireframe == true ? .on : .off
                        ) { [weak self] _ in
                            self?.toggleWireframe()
                        },
                        UIAction(
                            title: "Show Axes",
                            image: nil,
                            identifier: nil,
                            discoverabilityTitle: nil,
                            attributes: [],
                            state: document?.showAxes == true ? .on : .off
                        ) { [weak self] _ in
                            self?.toggleAxes()
                        },
                        UIAction(
                            title: "Copy Camera Settings",
                            image: nil,
                            identifier: nil,
                            discoverabilityTitle: nil,
                            attributes: [],
                            state: .off
                        ) { [weak self] _ in
                            self?.copyCamera()
                        },
                    ]
                ),
            ]
        )
        cameraButton.menu = cameraMenu
        if #available(iOS 16.0, *) {
            cameraButton.menuRepresentation = UIMenu(
                title: "Camera",
                image: UIImage(systemName: "camera"),
                children: cameraMenu.children
            )
        }
        // Update export menu
        exportMenuProvider?.updateExportMenu()
    }

    @objc func showModelInfo() {
        let sheet = UIAlertController(
            title: selectedGeometry.map { _ in
                "Selected Shape Info"
            } ?? "Scene Info",
            message: document?.modelInfo ?? "",
            preferredStyle: .alert
        )
        if let fileURL = selectedGeometry?.sourceLocation?.file ?? document?.documentFileURL {
            sheet.addAction(UIAlertAction(
                title: document?.isEditable ?? false ? "Open in Editor" : "View Source",
                style: .default
            ) { [weak self] _ in
                self?.openSourceView(withContentsOf: fileURL)
            })
        }
        sheet.addAction(UIAlertAction(
            title: "Done",
            style: .cancel
        ) { [weak self, weak sheet] _ in
            self?.restoreConsoleWhenDismissed(sheet)
        })
        presentModalHidingConsole(sheet)
    }

    func openSourceFile(_ fileURL: URL, in viewController: SourceViewController) {
        viewController.openSourceFile(fileURL, document: document)
    }

    func openSourceView(withContentsOf fileURL: URL) {
        if view.window?.windowScene?.appearsFullscreen == true {
            UIApplication.shared.closeSourceScenes()
            presentSourceViewModally(withContentsOf: fileURL)
            return
        }

        if let sceneDelegate = UIApplication.shared.connectedScenes
            .compactMap({ $0.delegate as? SourceSceneDelegate }).first
        {
            sceneDelegate.load(fileURL, document: document)
            if let windowScene = sceneDelegate.window?.windowScene,
               windowScene.shouldRequestSceneActivation
            {
                UIApplication.shared.requestSceneSessionActivation(
                    windowScene.session,
                    userActivity: SourceViewController.userActivity(for: fileURL),
                    options: nil,
                    errorHandler: nil
                )
            }
            return
        }

        if fileURL == document?.documentFileURL, let document {
            SourceDocumentRegistry.register(document, for: fileURL)
        }
        let options = UIScene.ActivationRequestOptions()
        let session = UIApplication.shared.openSessions.first {
            $0.configuration.name == sourceSceneConfigurationName
        }
        UIApplication.shared.requestSceneSessionActivation(
            session,
            userActivity: SourceViewController.userActivity(for: fileURL),
            options: options
        ) { [weak self] _ in
            Task { @MainActor in
                self?.presentSourceViewModally(withContentsOf: fileURL)
            }
        }
    }

    private func presentSourceViewModally(withContentsOf fileURL: URL) {
        let viewController = SourceViewController()
        viewController.modalPresentationStyle = .pageSheet
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.onDismiss = { [weak self, weak navigationController] in
            self?.restoreConsoleWhenDismissed(navigationController)
        }
        viewController.onOpenFailure = { [weak self, weak navigationController] in
            navigationController?.dismiss(animated: true) {
                self?.restoreConsoleWhenDismissed(navigationController)
            }
        }
        openSourceFile(fileURL, in: viewController)
        presentModalHidingConsole(navigationController)
    }

    func copyCamera() {
        guard let code = document?.cameraConfig(for: scnView) else {
            return
        }

        UIPasteboard.general.string = code
    }

    @objc func openSourceEditor() {
        if let url = document?.errorURL ??
            selectedGeometry?.sourceLocation?.file ??
            document?.fileURL
        {
            openSourceView(withContentsOf: url)
        }
    }

    @objc func grantAccess() {
        document?.grantAccess()
    }

    func toggleWireframe() {
        document?.showWireframe.toggle()
        rebuildMenu()
    }

    func toggleAxes() {
        document?.showAxes.toggle()
    }

    func toggleOrthographic() {
        document?.isOrthographic.toggle()
    }

    @objc private func handleTap(_ gestureRecognizer: UIGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        selectGeometry(at: location)
    }

    @objc func dismissDocumentViewController() {
        closeDocument()
    }

    func closeDocument(completion: ((Bool) -> Void)? = nil) {
        guard let document else {
            dismissDocument()
            completion?(true)
            return
        }

        guard !document.autosaveEnabled, document.hasUnsavedChanges else {
            dismissDocument {
                document.close(completionHandler: nil)
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
            document.savePendingChanges(allowSilentRecovery: false) { success in
                guard success else {
                    completion?(false)
                    return
                }
                self?.dismissDocument {
                    document.close(completionHandler: nil)
                    completion?(true)
                }
            }
        })
        alert.addAction(UIAlertAction(
            title: "Discard Changes",
            style: .destructive
        ) { [weak self] _ in
            document.discardPendingChanges()
            self?.dismissDocument {
                document.close(completionHandler: nil)
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
        presentModalHidingConsole(alert)
    }

    private func dismissDocument(completion: (() -> Void)? = nil) {
        let viewController = presentingViewController ?? self
        viewController.dismiss(animated: true) {
            viewController.view.window?.windowScene?.title = mainSceneTitle
            completion?()
        }
    }
}

#if os(visionOS)

private struct ConsoleOrnamentContainer: View {
    let viewController: ConsoleViewController
    let size: CGSize

    var body: some View {
        ConsoleOrnamentViewController(viewController: viewController)
            .frame(width: size.width, height: size.height)
            .glassBackgroundEffect(in: .rect(cornerRadius: 24), displayMode: .always)
    }
}

private struct ConsoleOrnamentViewController: UIViewControllerRepresentable {
    let viewController: ConsoleViewController

    func makeUIViewController(context _: Context) -> ConsoleViewController {
        viewController
    }

    func updateUIViewController(
        _: ConsoleViewController,
        context _: Context
    ) {}
}

#endif

extension DocumentViewController {
    private func selectionMenu(at location: CGPoint) -> UIMenu? {
        guard let context = selectionMenuContext(at: location) else {
            return nil
        }
        let children = selectionMenuElements(for: context.entries)
        guard !children.isEmpty else {
            return nil
        }

        let menu = UIMenu(title: "", children: children)
        if #available(iOS 16, *) {
            menu.preferredElementSize = .large
        }
        return menu
    }

    private func selectionMenuElements(for entries: [SelectionMenuEntry]) -> [UIMenuElement] {
        entries.compactMap {
            selectionMenuElement(for: $0)
        }
    }

    private func selectionMenuElement(for entry: SelectionMenuEntry) -> UIMenuElement? {
        let geometry = entry.geometry
        let title = entry.title
        let childElements = selectionMenuElements(for: entry.children)

        if !childElements.isEmpty {
            var children = [UIMenuElement]()
            if entry.isSelectable {
                children.append(selectionAction(for: geometry, title: title))
            }
            children.append(contentsOf: childElements)
            return UIMenu(title: title, children: children)
        }

        guard entry.isSelectable else {
            return nil
        }
        return selectionAction(for: geometry, title: title)
    }

    private func selectionAction(
        for geometry: Geometry,
        title: String
    ) -> UIAction {
        UIAction(
            title: title,
            image: nil,
            identifier: nil,
            discoverabilityTitle: nil,
            attributes: [],
            state: selectedGeometry === geometry ? .on : .off
        ) { [weak self] _ in
            self?.selectGeometry(geometry.scnNode)
        }
    }
}

extension DocumentViewController: @MainActor SCNCameraControllerDelegate {
    func cameraInertiaWillStart(for _: SCNCameraController) {
        rebuildMenu()
    }

    func cameraInertiaDidEnd(for _: SCNCameraController) {
        rebuildMenu()
    }
}
