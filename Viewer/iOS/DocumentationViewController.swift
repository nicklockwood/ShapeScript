//
//  DocumentationViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 12/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import UIKit
import WebKit

let documentationActivityType = "com.charcoaldesign.ShapeScriptViewer.documentation"
let documentationSceneConfigurationName = "Documentation Configuration"
let documentationSceneTitle = "ShapeScript Help"
private let documentationURLActivityKey = "url"

@MainActor
final class DocumentationViewController: UIViewController {
    private let initialURL: URL
    private var currentURL: URL
    private let webView = WKWebView(frame: .zero)
    private var backButton = UIBarButtonItem()
    private var forwardButton = UIBarButtonItem()
    private var reloadButton = UIBarButtonItem()
    private var safariButton = UIBarButtonItem()

    init(url: URL = onlineHelpURL) {
        self.initialURL = url
        self.currentURL = url
        super.init(nibName: nil, bundle: nil)
        title = documentationSceneTitle
        userActivity = Self.userActivity(for: url)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view = UIView()
        view.backgroundColor = .systemBackground
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: cssVariablesScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            primaryAction: UIAction { [weak self] _ in
                self?.webView.goBack()
            }
        )
        forwardButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.forward"),
            primaryAction: UIAction { [weak self] _ in
                self?.webView.goForward()
            }
        )
        reloadButton = UIBarButtonItem(
            systemItem: .refresh,
            primaryAction: UIAction { [weak self] _ in
                self?.webView.reload()
            }
        )
        safariButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            primaryAction: UIAction { [weak self] _ in
                guard let url = self?.currentDocumentationURL else {
                    return
                }
                UIApplication.shared.open(url)
            }
        )
        safariButton.accessibilityLabel = "Open in Safari"

        navigationItem.rightBarButtonItems = [safariButton, reloadButton]
        if navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in
                    self?.dismiss(animated: true)
                }
            )
        }
        toolbarItems = [
            backButton,
            forwardButton,
            .flexibleSpace(),
        ]
        navigationController?.isToolbarHidden = false

        updateButtons()
        load(initialURL)
    }

    func load(_ url: URL) {
        loadViewIfNeeded()
        currentURL = url
        userActivity = Self.userActivity(for: url)
        if let localURL = url.bundledDocumentationURL {
            webView.loadFileURL(
                localURL,
                allowingReadAccessTo: localURL.localReadAccessURL
            )
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        activity.addUserInfoEntries(from: [
            documentationURLActivityKey: currentDocumentationURL.absoluteString,
        ])
    }

    static func userActivity(for url: URL) -> NSUserActivity {
        let activity = NSUserActivity(activityType: documentationActivityType)
        activity.title = documentationSceneTitle
        activity.targetContentIdentifier = documentationActivityType
        activity.userInfo = [documentationURLActivityKey: url.absoluteString]
        return activity
    }

    static func url(from activity: NSUserActivity?) -> URL {
        guard let string = activity?.userInfo?[documentationURLActivityKey] as? String,
              let url = URL(string: string)
        else {
            return onlineHelpURL
        }
        return url
    }

    private var currentDocumentationURL: URL {
        guard let url = webView.url else {
            return currentURL
        }
        if url.isFileURL,
           let fileName = url.deletingPathExtension().lastPathComponent.addingPercentEncoding(
               withAllowedCharacters: .urlPathAllowed
           )
        {
            let documentationURL = fileName == "index" ?
                onlineHelpURL :
                onlineHelpURL.appendingPathComponent(fileName)
            guard let fragment = url.fragment,
                  var components = URLComponents(url: documentationURL, resolvingAgainstBaseURL: false)
            else {
                return documentationURL
            }
            components.fragment = fragment
            return components.url ?? documentationURL
        }
        return url
    }

    private func updateCSSVariables() {
        webView.evaluateJavaScript(cssVariablesScript, completionHandler: nil)
    }

    private var cssVariablesScript: String {
        let tintColor = view.tintColor.resolvedColor(with: traitCollection).cssColor
        return "document.documentElement.style.setProperty('--tint-color', '\(tintColor)');"
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?
            .hasDifferentColorAppearance(comparedTo: traitCollection) != false
        else {
            return
        }
        updateCSSVariables()
    }
}

extension DocumentationViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           !url.isFileURL,
           let localURL = url.bundledDocumentationURL
        {
            webView.loadFileURL(
                localURL,
                allowingReadAccessTo: localURL.localReadAccessURL
            )
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        if webView.url != nil {
            currentURL = currentDocumentationURL
        }
        updateCSSVariables()
        updateButtons()
        userActivity?.needsSave = true
    }

    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        updateButtons()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func updateButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        reloadButton.isEnabled = webView.url != nil
    }
}

private extension URL {
    var bundledDocumentationURL: URL? {
        guard isFileURL || isBundledDocumentationURL else {
            return nil
        }
        let fileName = deletingPathExtension().lastPathComponent
        let pageName = fileName.isEmpty || fileName == "ios" ? "index" : fileName
        guard let localURL = Bundle.main.url(
            forResource: pageName,
            withExtension: "html",
            subdirectory: "Documentation"
        ) else {
            return nil
        }

        guard let fragment,
              var components = URLComponents(url: localURL, resolvingAgainstBaseURL: false)
        else {
            return localURL
        }
        components.fragment = fragment
        return components.url
    }

    private var isBundledDocumentationURL: Bool {
        guard host == onlineHelpURL.host else {
            return false
        }
        let basePathComponents = onlineHelpURL.pathComponents.filter { $0 != "/" }
        let pathComponents = pathComponents.filter { $0 != "/" }
        return pathComponents.starts(with: basePathComponents)
    }

    var localReadAccessURL: URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return (components?.url ?? self).deletingLastPathComponent()
    }
}

private extension UIColor {
    var cssColor: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "rgba(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)), \(alpha))"
    }
}

@MainActor
@objc(DocumentationSceneDelegate)
final class DocumentationSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        windowScene.title = documentationSceneTitle

        let activity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
        let viewController = DocumentationViewController(url: DocumentationViewController.url(from: activity))
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.isToolbarHidden = false

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        self.window = window
    }

    func stateRestorationActivity(for _: UIScene) -> NSUserActivity? {
        documentationViewController?.userActivity
    }

    func load(_ url: URL) {
        documentationViewController?.load(url)
    }

    private var documentationViewController: DocumentationViewController? {
        (window?.rootViewController as? UINavigationController)?
            .viewControllers.first as? DocumentationViewController
    }
}

extension UIViewController {
    func presentDocumentation(_ url: URL) {
        if traitCollection.userInterfaceIdiom == .pad {
            if let sceneDelegate = UIApplication.shared.connectedScenes
                .compactMap({ $0.delegate as? DocumentationSceneDelegate })
                .first
            {
                sceneDelegate.load(url)
                return
            }

            let options = UIScene.ActivationRequestOptions()
            let session = UIApplication.shared.openSessions.first {
                $0.configuration.name == documentationSceneConfigurationName
            }
            UIApplication.shared.requestSceneSessionActivation(
                session,
                userActivity: DocumentationViewController.userActivity(for: url),
                options: options
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.presentDocumentationModally(url)
                }
            }
        } else {
            presentDocumentationModally(url)
        }
    }

    func presentDocumentationModally(_ url: URL) {
        let viewController = DocumentationViewController(url: url)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }
}
