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

protocol ExportMenuProvider {
    func updateExportMenu()
}

final class DocumentViewController: UIViewController {
    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var interfaceColor: UIColor = .black
    private(set) var scnView: SCNView = .init()
    private let consoleTextView: UITextView = .init()
    private let loadingIndicator: UIActivityIndicatorView = .init()

    @IBOutlet private var containerView: SplitView!
    @IBOutlet private var errorScrollView: UIScrollView!
    @IBOutlet private(set) var errorTextView: UITextView!
    @IBOutlet private(set) var grantAccessButton: UIButton!
    @IBOutlet private(set) var exportButton: UIBarButtonItem!
    @IBOutlet private var closeButton: UIBarButtonItem!
    @IBOutlet private var infoButton: UIBarButtonItem!
    @IBOutlet private var cameraButton: UIBarButtonItem!
    @IBOutlet private var editButton: UIBarButtonItem!
    @IBOutlet private var navigationBar: UINavigationBar?

    var document: Document? {
        didSet {
            document?.viewController = self
            updateEditButton()
            document?.rerender()
        }
    }

    lazy var cameraNode: SCNNode = makeCameraNode()

    weak var axesNode: SCNNode?

    var errorMessage: NSAttributedString? {
        didSet {
            guard let errorMessage else {
                errorScrollView.isHidden = true
                navigationBar?.tintColor = interfaceColor
                cameraButton.isEnabled = true
                infoButton.isEnabled = true
                exportButton.isEnabled = true
                return
            }
            errorTextView.attributedText = errorMessage
            errorScrollView.isHidden = false
            navigationBar?.tintColor = .white
            cameraButton.isEnabled = false
            infoButton.isEnabled = false
            exportButton.isEnabled = false
        }
    }

    private let log = NSMutableAttributedString()
    private var logLength = 0

    func clearLog() {
        logLength = 0
        log.mutableString.setString("")
        consoleTextView.text = ""
    }

    func appendLog(_ text: String) {
        if text.isEmpty {
            return
        }
        let logLimit = 20000
        let charCount = text.count
        logLength += charCount
        let location = log.length
        if logLength > logLimit {
            if logLength - charCount > logLimit {
                return
            }

            log.append(NSAttributedString(
                string: "Console limit exceeded. No further logs will be printed.",
                attributes: [
                    .foregroundColor: UIColor.red,
                    .font: UIFont.systemFont(ofSize: 13),
                ]
            ))
        } else {
            log.append(NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: UIColor.label,
                    .font: UIFont.systemFont(ofSize: 13),
                ]
            ))
        }
        consoleTextView.attributedText = log
        let range = NSRange(location: location, length: 1)
        DispatchQueue.main.async {
            if self.containerView.heights.count > 1 {
                self.containerView.heights[1] =
                    min(150, self.consoleTextView.contentSize.height)
            }
            self.consoleTextView.scrollRangeToVisible(range)
        }
    }

    func updateModals() {
        var presentedViewController = presentedViewController
        while let vc = presentedViewController?.presentedViewController {
            presentedViewController = vc
        }
        if let navController = presentedViewController as? UINavigationController,
           let viewController = navController.viewControllers.first as? SourceViewController,
           let fileURL = viewController.document?.fileURL
        {
            openSourceFile(fileURL, in: viewController)
        } else {
            presentedViewController?.dismiss(animated: true) { [weak self] in
                self?.updateModals()
            }
        }
    }

    var isLoading = false {
        didSet {
            guard isLoading != oldValue else {
                return
            }
            if #available(iOS 16, *) {
                // Hide the bar item to prevent extended border on iOS 26
                navigationBar?.topItem?.leftBarButtonItems?.first(where: {
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
                if consoleTextView.superview == nil {
                    consoleTextView.frame.size.width = scnView.frame.width
                    consoleTextView.sizeToFit()
                    consoleTextView.isEditable = false
                    consoleTextView.textContainerInset = UIEdgeInsets(
                        top: 5,
                        left: 5,
                        bottom: 5,
                        right: 5
                    )
                    let height = consoleTextView.frame.height + view.safeAreaInsets.bottom
                    containerView.addArrangedSubview(
                        consoleTextView,
                        height: height
                    )
                }
            } else {
                containerView.removeArrangedSubview(consoleTextView)
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
        editButton?.image = UIImage(systemName: document?.isEditable ?? false ?
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
        navigationBar?.topItem?.leftBarButtonItems?.append(loadingItem)
        navigationBar?.standardAppearance.configureWithTransparentBackground()
        if let exportMenuProvider {
            exportMenuProvider.updateExportMenu()
        } else {
            navigationBar?.topItem?.rightBarButtonItems?.removeAll(where: {
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
        refreshGeometry()

        // configure camera menu
        rebuildMenu()

        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        if self as Any is ExportMenuProvider {
            scheduleCameraMovedTimer()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkDocumentVersion()
    }

    func presentError(_ error: Error, completionHandler: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: "Warning",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "OK",
            style: .default
        ) { _ in
            completionHandler?()
        })
        present(alert, animated: true)
    }

    private var _cameraHadMoved = false
    private func scheduleCameraMovedTimer() {
        Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            if self.cameraHasMoved != self._cameraHadMoved {
                self._cameraHadMoved = self.cameraHasMoved
                self.rebuildMenu()
            }
            self.scheduleCameraMovedTimer()
        }
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

    @IBAction func showModelInfo() {
        let sheet = UIAlertController(
            title: selectedGeometry.map { _ in
                "Selected Shape Info"
            } ?? "Scene Info",
            message: document?.modelInfo ?? "",
            preferredStyle: .alert
        )
        if let fileURL = selectedGeometry?.sourceLocation?.file ?? document?.fileURL {
            sheet.addAction(UIAlertAction(
                title: "View Source",
                style: .default
            ) { [weak self] _ in
                self?.openSourceView(withContentsOf: fileURL)
            })
        }
        sheet.addAction(UIAlertAction(
            title: "Done",
            style: .cancel
        ) { [weak sheet] _ in
            sheet?.dismiss(animated: true)
        })
        present(sheet, animated: true, completion: {})
    }

    func openSourceFile(_ fileURL: URL, in viewController: SourceViewController) {
        if fileURL == document?.fileURL {
            viewController.document = document
        } else {
            let document = Document(fileURL: fileURL)
            document.open { success in
                if success {
                    viewController.document = document
                } else {
                    viewController.dismiss(animated: true)
                }
            }
        }
    }

    func openSourceView(withContentsOf fileURL: URL) {
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyBoard
            .instantiateViewController(withIdentifier: "SourceViewController") as! SourceViewController
        openSourceFile(fileURL, in: viewController)
        viewController.modalPresentationStyle = .pageSheet
        let navigationController = UINavigationController(rootViewController: viewController)
        present(navigationController, animated: true, completion: nil)
    }

    @IBAction func resetCamera() {
        updateAxesAndCamera()
        resetView()
        rebuildMenu()
    }

    @IBAction func copyCamera() {
        guard let code = document?.cameraConfig(for: scnView) else {
            return
        }

        UIPasteboard.general.string = code
    }

    @IBAction func openSourceEditor() {
        if let url = document?.errorURL ??
            selectedGeometry?.sourceLocation?.file ??
            document?.fileURL
        {
            openSourceView(withContentsOf: url)
        }
    }

    @IBAction func grantAccess() {
        document?.grantAccess()
    }

    @IBAction func toggleWireframe() {
        document?.showWireframe.toggle()
        rebuildMenu()
    }

    @IBAction func toggleAxes() {
        document?.showAxes.toggle()
    }

    @IBAction func toggleOrthographic() {
        document?.isOrthographic.toggle()
    }

    @objc private func handleTap(_ gestureRecognizer: UIGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        selectGeometry(at: location)
    }

    @IBAction func dismissDocumentViewController() {
        dismiss(animated: true) {
            self.document?.close(completionHandler: nil)
        }
    }
}

extension DocumentViewController: SCNCameraControllerDelegate {
    func cameraInertiaWillStart(for _: SCNCameraController) {
        rebuildMenu()
    }

    func cameraInertiaDidEnd(for _: SCNCameraController) {
        rebuildMenu()
    }
}
