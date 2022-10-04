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

class DocumentViewController: UIViewController {
    let scnScene = SCNScene()
    var renderTimer: Timer?
    private(set) var interfaceColor: UIColor = .black
    private(set) var scnView: SCNView!
    private var consoleTextView = UITextView()

    @IBOutlet private var containerView: SplitView!
    @IBOutlet private var errorScrollView: UIScrollView!
    @IBOutlet private var errorTextView: UITextView!
    @IBOutlet private var loadingIndicator: UIActivityIndicatorView!
    @IBOutlet private var grantAccessButton: UIButton!
    @IBOutlet private var closeButton: UIButton!
    @IBOutlet private var infoButton: UIButton!
    @IBOutlet private var cameraButton: UIButton!

    var document: Document? {
        didSet {
            document?.viewController = self
        }
    }

    lazy var cameraNode: SCNNode = makeCameraNode()

    weak var axesNode: SCNNode?

    var errorMessage: NSAttributedString? {
        didSet {
            guard let errorMessage = errorMessage else {
                errorScrollView.isHidden = true
                closeButton.tintColor = interfaceColor
                return
            }
            errorTextView.attributedText = errorMessage
            errorScrollView.isHidden = false
            closeButton.tintColor = .white
        }
    }

    private let log = NSMutableAttributedString()
    private var logLength = 0

    func clearLog() {
        logLength = 0
        log.mutableString.setString("")
        consoleTextView.text = ""
    }

    func dismissModals(animated: Bool = true) {
        var presentedViewController = presentedViewController
        while let vc = presentedViewController?.presentedViewController {
            presentedViewController = vc
        }
        presentedViewController?.dismiss(animated: animated) { [weak self] in
            self?.dismissModals(animated: animated)
        }
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
            self.containerView.heights[1] =
                min(150, self.consoleTextView.contentSize.height)
            self.consoleTextView.scrollRangeToVisible(range)
        }
    }

    var showAccessButton = false {
        didSet {
            guard showAccessButton != oldValue else {
                return
            }
            grantAccessButton.isHidden = !showAccessButton
            errorTextView.backgroundColor = showAccessButton ?
                UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) :
                UIColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        }
    }

    var isLoading = false {
        didSet {
            guard isLoading != oldValue else {
                return
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
            newValue?.configureProperty(scnScene.background)
            updateInterfaceColor()
        }
    }

    var isBrightBackground: Bool {
        let color = Color(Document.backgroundColor)
        let brightness = background?.brightness(over: color) ?? color.brightness
        return brightness > 0.5
    }

    func updateInterfaceColor() {
        interfaceColor = UIColor(isBrightBackground ? Color.black : .white)
        closeButton.tintColor = errorMessage.map { _ in .white } ?? interfaceColor
        cameraButton.tintColor = interfaceColor
        infoButton.tintColor = interfaceColor
        loadingIndicator.color = interfaceColor
        setNeedsStatusBarAppearanceUpdate()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        errorTextView.textContainerInset = UIEdgeInsets(
            top: view.safeAreaInsets.top + 60,
            left: max(view.safeAreaInsets.left + 15, 20),
            bottom: view.safeAreaInsets.bottom + 20,
            right: max(view.safeAreaInsets.right + 15, 20)
        )
        if !cameraHasMoved {
            updateAxesAndCamera()
            resetView()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        containerView.backgroundColor = .black

        // create view
        scnView = SCNView(frame: containerView.bounds, options: [:])
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addArrangedSubview(scnView, height: nil)

        // set the scene to the view
        scnView.scene = scnScene

        // configure the view
        scnView.backgroundColor = Document.backgroundColor
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X // .multisampling16X
        scnView.allowsCameraControl = geometry != nil
        updateInterfaceColor()
        updateAxesAndCamera()
        resetView()

        // configure camera button
        cameraButton.showsMenuAsPrimaryAction = true
        rebuildMenu()

        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        // observe foregrounding
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    private func rebuildMenu() {
        let cameras: [Camera]
        if let document = document {
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
                state: self.camera == camera ? .on : .off
            ) { [weak self] _ in
                let camera = cameras[i]
                if camera == self?.document?.camera {
                    self?.resetCamera()
                } else {
                    self?.document?.camera = camera
                }
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
                    attributes: [],
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
                            state: isOrthographic ? .on : .off
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
                            title: "Copy Settings",
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if document?.documentState == .normal {
            reload()
        }
    }

    @objc private func reload() {
        document?.open(completionHandler: { _ in })
    }

    @IBAction func showModelInfo() {
        let sheet = UIAlertController(
            title: selectedGeometry.map { _ in
                "Selected Object Info"
            } ?? "Model Info",
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

    func openSourceView(withContentsOf _: URL) {
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyBoard.instantiateViewController(withIdentifier: "SourceViewController") as! SourceViewController
        viewController.document = document
        viewController.modalPresentationStyle = .pageSheet
        let navigationController = UINavigationController(rootViewController: viewController)
        present(navigationController, animated: true, completion: nil)
    }

    @IBAction func resetCamera() {
        updateAxesAndCamera()
        resetView()
    }

    @IBAction func copyCamera() {
        guard let code = document?.cameraConfig(
            for: scnView,
            contentsScale: scnView.contentScaleFactor
        ) else {
            return
        }

        UIPasteboard.general.string = code
    }

    @IBAction func grantAccess() {
        document?.grantAccess()
    }

    @IBAction func toggleWireframe() {
        document?.showWireframe.toggle()
    }

    @IBAction func toggleAxes() {
        document?.showAxes.toggle()
    }

    @IBAction func toggleOrthographic() {
        document?.isOrthographic.toggle()
    }

    @objc private func handleTap(_ gestureRecognizer: UIGestureRecognizer) {
        let location = gestureRecognizer.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [:])
        selectGeometry(hitResults.first?.node)
    }

    @IBAction func dismissDocumentViewController() {
        dismiss(animated: true) {
            self.document?.close(completionHandler: nil)
        }
    }
}
