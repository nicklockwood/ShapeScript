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
    private let loadingIndicator: UIActivityIndicatorView = .init()
    private let containerView: SplitView = .init()
    private(set) var exportButton: UIBarButtonItem = .init()
    private weak var warningView: UIView?
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
            guard let errorMessage else {
                errorTextView.isHidden = true
                navigationBar?.tintColor = interfaceColor
                cameraButton.isEnabled = true
                exportButton.isEnabled = true
                return
            }
            errorTextView.attributedText = errorMessage
            errorTextView.isHidden = false
            navigationBar?.tintColor = .white
            cameraButton.isEnabled = false
            exportButton.isEnabled = false
        }
    }

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
            updateLoadingButton()
            if isLoading {
                loadingIndicator.startAnimating()
            } else {
                loadingIndicator.stopAnimating()
                refreshView()
            }
        }
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
                updateAxesAndCamera()
                rebuildMenu()
            }
        }
    }

    var isOrthographic = false {
        didSet {
            if isOrthographic != oldValue {
                refreshOrthographic()
                rebuildMenu()
            }
        }
    }

    var camera: Camera = .default {
        didSet {
            if camera != oldValue {
                updateAxesAndCamera()
                resetView()
                rebuildMenu()
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
        loadingIndicator.color = interfaceColor
        grantAccessButton.tintColor = .white
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        #endif
    }

    func updateEditButton() {
        editButton.image = UIImage(systemName: document?.isEditable ?? false ?
            "square.and.pencil" : "doc.plaintext")
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
        let items = isLoading ? [closeButton, loadingItem] : [closeButton]
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

    var geometry: Geometry? {
        didSet {
            refreshGeometry()
            rebuildMenu()
        }
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
            style: .plain,
            target: self,
            action: #selector(showModelInfo)
        )
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
        updateInterfaceColor()
        if !cameraHasMoved {
            updateAxesAndCamera()
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
        loadingItem = UIBarButtonItem(customView: loadingIndicator)
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
        refreshGeometry()

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
        checkDocumentVersion()
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

    func showWarning(_ message: String, onDismiss: @escaping @MainActor @Sendable () -> Void) {
        dismissWarning(notify: false)
        warningDismissHandler = onDismiss

        let banner = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.clipsToBounds = true
        banner.layer.cornerRadius = 18
        banner.layer.cornerCurve = .continuous

        let tintView = UIView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.22)
        banner.contentView.addSubview(tintView)

        let imageView = UIImageView(
            image: UIImage(systemName: "exclamationmark.triangle.fill")
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Dismiss"
        closeButton.addTarget(
            self,
            action: #selector(dismissWarningPressed),
            for: .touchUpInside
        )

        banner.contentView.addSubview(imageView)
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
        regularWarningConstraints = [
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

            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: banner.contentView.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: banner.contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        updateWarningLayoutConstraints()
    }

    @objc private func dismissWarningPressed() {
        dismissWarning(notify: true)
    }

    private func dismissWarning(notify: Bool) {
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
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            warningView.alpha = 0
            warningView.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            NSLayoutConstraint.deactivate(self.compactWarningConstraints + self.regularWarningConstraints)
            warningView.removeFromSuperview()
            self.compactWarningConstraints.removeAll()
            self.regularWarningConstraints.removeAll()
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
        if #available(iOS 15, *) {
            dismissSheetConsole(restoreIfNeeded: true)
        } else {
            containerView.removeArrangedSubview(consoleViewController.consoleView)
            consoleViewController.removeFromParent()
        }
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

    @available(iOS 15, *)
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
        }

        guard let presentedViewController else {
            presentModal()
            return
        }

        if #available(iOS 15, *), presentedViewController === consoleViewController {
            dismissSheetConsole(animated: animated, completion: presentModal)
        } else if let sourceViewController = presentedSourceViewController() {
            sourceViewController.present(viewController, animated: animated) { [weak self] in
                self?.isPreparingModalPresentation = false
                completion?()
            }
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
        cameraButton.menu = UIMenu(
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
        openSourceFile(fileURL, in: viewController)
        viewController.modalPresentationStyle = .pageSheet
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.onDismiss = { [weak self, weak navigationController] in
            self?.restoreConsoleWhenDismissed(navigationController)
        }
        presentModalHidingConsole(navigationController)
    }

    func resetCamera() {
        updateAxesAndCamera()
        resetView()
        rebuildMenu()
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
        let viewController = presentingViewController ?? self
        viewController.dismiss(animated: true) {
            viewController.view.window?.windowScene?.title = mainSceneTitle
            self.document?.close(completionHandler: nil)
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
        guard let document else {
            return nil
        }

        let geometries = selectableGeometries(at: location)
        let namesByGeometry = selectionMenuNames(for: document)
        let children = geometries.isEmpty ?
            selectionMenuElements(
                forChildrenOf: document.geometry,
                document: document,
                namesByGeometry: namesByGeometry
            ) :
            selectionMenuElements(
                for: geometries,
                document: document,
                namesByGeometry: namesByGeometry
            )
        guard !children.isEmpty else {
            return nil
        }

        let menu = UIMenu(title: "Select Shape", children: children)
        if #available(iOS 16, *) {
            menu.preferredElementSize = .large
        }
        return menu
    }

    private func selectionMenuElements(
        for geometries: [Geometry],
        document: Document,
        namesByGeometry: [ObjectIdentifier: String]
    ) -> [UIMenuElement] {
        geometries.compactMap { geometry in
            guard !geometries.contains(where: { geometry.isDescendant(of: $0) }) else {
                return nil
            }
            return selectionMenuElement(
                for: geometry,
                in: geometries,
                document: document,
                namesByGeometry: namesByGeometry
            )
        }
    }

    private func selectionMenuElements(
        forChildrenOf geometry: Geometry,
        document: Document,
        namesByGeometry: [ObjectIdentifier: String]
    ) -> [UIMenuElement] {
        geometry.children.compactMap {
            selectionMenuElement(
                for: $0,
                document: document,
                namesByGeometry: namesByGeometry
            )
        }
    }

    private func selectionMenuElement(
        for geometry: Geometry,
        in geometries: [Geometry],
        document: Document,
        namesByGeometry: [ObjectIdentifier: String]
    ) -> UIMenuElement? {
        guard geometry.isVisibleInSelectionMenu else {
            return nil
        }
        let focus = document.geometry.childIsFocused
        let isSelectable = geometry.isSelectableInSelectionMenu(focus: focus)
        let title = namesByGeometry[ObjectIdentifier(geometry)] ?? document.geometryName(for: geometry)
        let childGeometries = geometries.filter {
            $0 !== geometry && $0.isDescendant(of: geometry)
        }
        let childElements = selectionMenuElements(
            for: childGeometries,
            document: document,
            namesByGeometry: namesByGeometry
        )

        if geometry.hasSelectionMenuChildren, !childElements.isEmpty {
            var children = [UIMenuElement]()
            if isSelectable {
                children.append(selectionAction(for: geometry, title: title))
            }
            children.append(contentsOf: childElements)
            return UIMenu(title: title, children: children)
        }

        return selectionAction(for: geometry, title: title, isEnabled: isSelectable)
    }

    private func selectionMenuElement(
        for geometry: Geometry,
        document: Document,
        namesByGeometry: [ObjectIdentifier: String]
    ) -> UIMenuElement? {
        guard geometry.isVisibleInSelectionMenu else {
            return nil
        }
        let focus = document.geometry.childIsFocused
        let isSelectable = geometry.isSelectableInSelectionMenu(focus: focus)
        let title = namesByGeometry[ObjectIdentifier(geometry)] ?? document.geometryName(for: geometry)
        let childElements = geometry.hasSelectionMenuChildren ? selectionMenuElements(
            forChildrenOf: geometry,
            document: document,
            namesByGeometry: namesByGeometry
        ) : []

        if !childElements.isEmpty {
            var children = [UIMenuElement]()
            if isSelectable {
                children.append(selectionAction(for: geometry, title: title))
            }
            children.append(contentsOf: childElements)
            return UIMenu(title: title, children: children)
        }

        return selectionAction(for: geometry, title: title, isEnabled: isSelectable)
    }

    private func selectionMenuNames(for document: Document) -> [ObjectIdentifier: String] {
        var countsByType = [String: Int]()
        var namesByGeometry = [ObjectIdentifier: String]()
        document.enumerateSelectionMenuGeometries(in: document.geometry) { geometry in
            namesByGeometry[ObjectIdentifier(geometry)] = document.geometryName(
                for: geometry,
                in: &countsByType
            )
        }
        return namesByGeometry
    }

    private func selectionAction(
        for geometry: Geometry,
        title: String,
        isEnabled: Bool = true
    ) -> UIAction {
        UIAction(
            title: title,
            image: nil,
            identifier: nil,
            discoverabilityTitle: nil,
            attributes: isEnabled ? [] : [.disabled],
            state: selectedGeometry === geometry ? .on : .off
        ) { [weak self] _ in
            guard isEnabled else {
                return
            }
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
