//
//  DocumentViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript
import UIKit

@MainActor
protocol ExportMenuProvider {
    func updateExportMenu()
}

@MainActor
final class DocumentViewController: UIViewController, DocumentViewControllerProtocol,
    UIAdaptivePresentationControllerDelegate
{
    static var documentBackgroundColor: Color {
        Document.documentBackgroundColor
    }

    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var interfaceColor: UIColor = .black
    private(set) var scnView: SCNView = .init()
    private let consoleViewController: ConsoleViewController = .init()
    private var isPreparingModalPresentation = false
    private let loadingIndicator: UIActivityIndicatorView = .init()
    private let containerView: SplitView = .init()
    private(set) var exportButton: UIBarButtonItem = .init()

    let errorTextView: UITextView = .init()
    let grantAccessButton: UIButton = .init(type: .system)

    private var closeButton: UIBarButtonItem = .init()
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
            if self.consoleViewController.consoleView.superview === self.containerView,
               self.containerView.heights.count > 1
            {
                self.containerView.heights[1] =
                    self.consoleViewController.inlineHeight(maximumHeight: 150)
            }
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
            if #available(iOS 16, *) {
                // Hide the bar item to prevent extended border on iOS 26
                navigationItem.leftBarButtonItems?.first(where: {
                    $0.customView === loadingIndicator
                })?.isHidden = !isLoading
            }
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

    var isBrightBackground: Bool {
        let color = Color(Document.backgroundColor)
        let brightness = background?.brightness(over: color) ?? color.brightness
        return brightness > 0.5
    }

    var exportMenuProvider: ExportMenuProvider? {
        self as Any as? ExportMenuProvider
    }

    func updateInterfaceColor() {
        interfaceColor = UIColor(isBrightBackground ? Color.black : .white)
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
        rootView.backgroundColor = .systemBackground

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
        navigationItem.rightBarButtonItems = [exportButton, cameraButton, infoButton, editButton]

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
        let loadingItem = UIBarButtonItem(customView: loadingIndicator)
        if #available(iOS 16, *) {
            loadingItem.isHidden = !isLoading
        }
        navigationItem.leftBarButtonItems?.append(loadingItem)
        navigationBar?.standardAppearance.configureWithTransparentBackground()
        if let exportMenuProvider {
            exportMenuProvider.updateExportMenu()
        } else {
            navigationItem.rightBarButtonItems?.removeAll(where: {
                $0 === exportButton
            })
        }

        // configure the view
        containerView.backgroundColor = Document.backgroundColor
        scnView.backgroundColor = .clear // Important!
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

    private func presentConsole() {
        if #available(iOS 16, *) {
            presentSheetConsole()
        } else {
            presentInlineConsole()
        }
    }

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
        if #available(iOS 15, *) {
            dismissSheetConsole(restoreIfNeeded: true)
        } else {
            containerView.removeArrangedSubview(consoleViewController.consoleView)
            consoleViewController.removeFromParent()
        }
    }

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

    private func restoreConsoleWhenDismissed(
        _: UIViewController?,
        remainingAttempts: Int = 40
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if self.presentedViewController == nil {
                self.restoreConsoleAfterModalIfNeeded()
            } else if remainingAttempts > 0 {
                self.restoreConsoleWhenDismissed(
                    nil,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }

    private func presentModalHidingConsole(
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
        let cameras: [Camera]
        if let document {
            cameras = document.cameras
        } else {
            cameras = CameraType.allCases.map {
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
        if fileURL == document?.documentFileURL {
            viewController.document = document
        } else {
            let document = Document(fileURL: fileURL)
            let sourceViewController = viewController
            document.open { success in
                if success {
                    sourceViewController.perform(
                        #selector(SourceViewController.setOpenedDocument(_:)),
                        on: .main,
                        with: document,
                        waitUntilDone: false
                    )
                }
            }
        }
    }

    func openSourceView(withContentsOf fileURL: URL) {
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
        let completion: () -> Void = {
            self.document?.close(completionHandler: nil)
        }
        if let presentingViewController {
            presentingViewController.dismiss(animated: true, completion: completion)
        } else {
            dismiss(animated: true, completion: completion)
        }
    }
}

extension DocumentViewController: @preconcurrency SCNCameraControllerDelegate {
    func cameraInertiaWillStart(for _: SCNCameraController) {
        rebuildMenu()
    }

    func cameraInertiaDidEnd(for _: SCNCameraController) {
        rebuildMenu()
    }
}
