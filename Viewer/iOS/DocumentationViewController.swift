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
    private var lastLoadedDocumentationURL: URL
    private lazy var searchIndex = DocumentationSearchIndex()
    private let searchResultsViewController = DocumentationSearchResultsViewController()
    private lazy var searchController = UISearchController(searchResultsController: searchResultsViewController)
    private let webView = WKWebView(frame: .zero)
    private let loadingOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let loadingTitleLabel = UILabel()
    private let loadingMessageLabel = UILabel()
    private let loadingCancelButton = UIButton(type: .system)
    private let loadingRetryButton = UIButton(type: .system)
    private var externalLoadingURL: URL?
    private var backButton = UIBarButtonItem()
    private var forwardButton = UIBarButtonItem()
    private var reloadButton = UIBarButtonItem()
    private var safariButton = UIBarButtonItem()

    init(url: URL = onlineHelpURL) {
        self.initialURL = url
        self.currentURL = url
        self.lastLoadedDocumentationURL = url
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
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.alpha = 0
        loadingOverlay.isHidden = true
        view = UIView()
        view.backgroundColor = .systemBackground
        view.addSubview(webView)
        view.addSubview(loadingOverlay)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        searchResultsViewController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = true
        searchController.searchBar.placeholder = "Search Help"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        configureLoadingOverlay()

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

        updateNavigationButtons(animated: false)
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
        if let localURL = url.bundledDocumentationURL {
            setCurrentDocumentationURL(url)
            hideExternalLoadingOverlay()
            webView.loadFileURL(
                localURL,
                allowingReadAccessTo: localURL.localReadAccessURL
            )
        } else {
            showExternalLoadingOverlay(for: url)
            updateNavigationButtons()
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

    private func setCurrentDocumentationURL(_ url: URL) {
        currentURL = url
        lastLoadedDocumentationURL = url
        userActivity = Self.userActivity(for: url)
        updateNavigationButtons()
    }

    private func updateCSSVariables() {
        webView.evaluateJavaScript(cssVariablesScript, completionHandler: nil)
    }

    private func updateNavigationButtons(animated: Bool = true) {
        let items = shouldShowReloadButton ?
            [safariButton, reloadButton] :
            [safariButton]
        let currentItems = navigationItem.rightBarButtonItems ?? []
        guard currentItems.count != items.count ||
            !zip(currentItems, items).allSatisfy({ $0 === $1 })
        else {
            return
        }
        navigationItem.setRightBarButtonItems(items, animated: animated)
    }

    private var shouldShowReloadButton: Bool {
        if let externalLoadingURL {
            return shouldShowLoadingOverlay(for: externalLoadingURL)
        }
        guard let url = webView.url else {
            return shouldShowLoadingOverlay(for: currentURL)
        }
        return shouldShowLoadingOverlay(for: url)
    }

    private func configureLoadingOverlay() {
        let contentView = loadingOverlay.contentView
        let buttonStack = UIStackView(arrangedSubviews: [
            loadingCancelButton,
            loadingRetryButton,
        ])
        let stackView = UIStackView(arrangedSubviews: [
            loadingIndicator,
            loadingTitleLabel,
            loadingMessageLabel,
            buttonStack,
        ])

        loadingTitleLabel.font = .preferredFont(forTextStyle: .headline)
        loadingTitleLabel.textAlignment = .center
        loadingTitleLabel.text = "Loading"

        loadingMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        loadingMessageLabel.textAlignment = .center
        loadingMessageLabel.textColor = .secondaryLabel
        loadingMessageLabel.numberOfLines = 2

        loadingCancelButton.setTitle("Cancel", for: .normal)
        loadingCancelButton.addAction(UIAction { [weak self] _ in
            self?.cancelExternalLoad()
        }, for: .touchUpInside)

        loadingRetryButton.setTitle("Retry", for: .normal)
        loadingRetryButton.addAction(UIAction { [weak self] _ in
            self?.retryExternalLoad()
        }, for: .touchUpInside)

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalSpacing
        buttonStack.spacing = 24

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            loadingMessageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
    }

    private func showExternalLoadingOverlay(for url: URL) {
        externalLoadingURL = url
        loadingMessageLabel.text = url.host ?? url.absoluteString
        loadingRetryButton.isHidden = true
        loadingIndicator.startAnimating()
        setLoadingOverlayHidden(false)
    }

    private func showExternalLoadFailure(for url: URL, error: Error) {
        externalLoadingURL = url
        loadingTitleLabel.text = "Could Not Load Page"
        loadingMessageLabel.text = error.localizedDescription
        loadingRetryButton.isHidden = false
        loadingIndicator.stopAnimating()
        setLoadingOverlayHidden(false)
    }

    private func hideExternalLoadingOverlay() {
        externalLoadingURL = nil
        loadingTitleLabel.text = "Loading"
        loadingIndicator.stopAnimating()
        setLoadingOverlayHidden(true)
    }

    private func setLoadingOverlayHidden(_ hidden: Bool) {
        if !hidden {
            loadingOverlay.isHidden = false
        }
        UIView.animate(withDuration: 0.2) {
            self.loadingOverlay.alpha = hidden ? 0 : 1
        } completion: { _ in
            self.loadingOverlay.isHidden = hidden
        }
    }

    private func cancelExternalLoad() {
        webView.stopLoading()
        hideExternalLoadingOverlay()
        restoreCurrentDocumentationPage()
        updateNavigationButtons()
    }

    private func retryExternalLoad() {
        guard let url = externalLoadingURL else {
            return
        }
        loadingTitleLabel.text = "Loading"
        loadingRetryButton.isHidden = true
        loadingIndicator.startAnimating()
        load(url)
    }

    private func load(_ result: DocumentationSearchResult) {
        searchController.isActive = false
        searchController.searchBar.text = ""
        load(result.url)
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

extension DocumentationViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchResultsViewController.results = searchIndex.search(searchController.searchBar.text ?? "")
    }
}

extension DocumentationViewController: DocumentationSearchResultsViewControllerDelegate {
    fileprivate func documentationSearchResultsViewController(
        _: DocumentationSearchResultsViewController,
        didSelect result: DocumentationSearchResult
    ) {
        load(result)
    }
}

private struct DocumentationSearchResult {
    let title: String
    let subtitle: String?
    let snippet: String
    let url: URL
    let score: Int
}

private struct DocumentationSearchEntry {
    let title: String
    let heading: String?
    let body: String
    let url: URL

    func result(matching query: String, terms: [String]) -> DocumentationSearchResult? {
        let searchableTitle = title.normalizedForDocumentationSearch
        let searchableHeading = heading?.normalizedForDocumentationSearch ?? ""
        let searchableBody = body.normalizedForDocumentationSearch
        var score = 0

        for term in terms {
            if searchableTitle == term {
                score += 60
            } else if searchableTitle.contains(term) {
                score += 30
            }
            if searchableHeading == term {
                score += 50
            } else if searchableHeading.contains(term) {
                score += 24
            }
            if searchableBody.contains(term) {
                score += 6
            }
        }

        if searchableTitle.contains(query) {
            score += 18
        }
        if searchableHeading.contains(query) {
            score += 14
        }
        if searchableBody.contains(query) {
            score += 10
        }

        guard score > 0 else {
            return nil
        }
        return DocumentationSearchResult(
            title: heading ?? title,
            subtitle: heading == nil ? nil : title,
            snippet: body.snippet(matching: terms),
            url: url,
            score: score
        )
    }
}

private final class DocumentationSearchIndex {
    private lazy var entries = loadEntries()

    func search(_ text: String) -> [DocumentationSearchResult] {
        let query = text.normalizedForDocumentationSearch
        let terms = query.split(separator: " ").map(String.init)
        guard !terms.isEmpty else {
            return []
        }
        return entries.compactMap { $0.result(matching: query, terms: terms) }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return ($0.subtitle ?? "") < ($1.subtitle ?? "")
            }
            .prefix(50)
            .map { $0 }
    }

    private func loadEntries() -> [DocumentationSearchEntry] {
        guard let directory = Bundle.main.resourceURL?
            .appendingPathComponent("Documentation", isDirectory: true),
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "html" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap(loadEntries)
    }

    private func loadEntries(from url: URL) -> [DocumentationSearchEntry] {
        guard let html = try? String(contentsOf: url) else {
            return []
        }

        let title = html.firstMatch(for: #"<h1[^>]*>(.*?)</h1>"#)?
            .plainDocumentationText ?? url.deletingPathExtension().lastPathComponent
        let sections = html.sectionsForDocumentationSearch
        if sections.isEmpty {
            return [
                DocumentationSearchEntry(
                    title: title,
                    heading: nil,
                    body: html.plainDocumentationText,
                    url: url
                ),
            ]
        }

        return sections.map { section in
            let sectionURL: URL
            if let fragment = section.fragment,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            {
                components.fragment = fragment
                sectionURL = components.url ?? url
            } else {
                sectionURL = url
            }
            return DocumentationSearchEntry(
                title: title,
                heading: section.heading,
                body: section.body,
                url: sectionURL
            )
        }
    }
}

@MainActor
private protocol DocumentationSearchResultsViewControllerDelegate: AnyObject {
    func documentationSearchResultsViewController(
        _ viewController: DocumentationSearchResultsViewController,
        didSelect result: DocumentationSearchResult
    )
}

private final class DocumentationSearchResultsViewController: UITableViewController {
    weak var delegate: DocumentationSearchResultsViewControllerDelegate?
    var results: [DocumentationSearchResult] = [] {
        didSet {
            tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Result")
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        results.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Result", for: indexPath)
        let result = results[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = result.title
        content.secondaryText = [result.subtitle, result.snippet]
            .compactMap { $0 }
            .joined(separator: "\n")
        content.secondaryTextProperties.numberOfLines = 3
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.documentationSearchResultsViewController(self, didSelect: results[indexPath.row])
    }
}

private struct DocumentationSearchSection {
    let heading: String?
    let fragment: String?
    let body: String
}

private extension String {
    var normalizedForDocumentationSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var plainDocumentationText: String {
        replacingOccurrences(
            of: #"<script[\s\S]*?</script>"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"<style[\s\S]*?</style>"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: #"&#39;|&apos;"#, with: "'", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sectionsForDocumentationSearch: [DocumentationSearchSection] {
        let pattern = #"<h([1-6])(?:\s+[^>]*)?>(.*?)</h\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsString = self as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: self, range: range)
        guard !matches.isEmpty else {
            return []
        }

        return matches.indices.compactMap { index in
            let match = matches[index]
            let nextStart = matches.dropFirst(index + 1).first?.range.location ?? nsString.length
            let bodyRange = NSRange(
                location: match.range.upperBound,
                length: max(0, nextStart - match.range.upperBound)
            )
            let headingHTML = nsString.substring(with: match.range(at: 2))
            let heading = headingHTML.plainDocumentationText
            let body = nsString.substring(with: bodyRange).plainDocumentationText
            guard !heading.isEmpty || !body.isEmpty else {
                return nil
            }
            return DocumentationSearchSection(
                heading: heading.isEmpty ? nil : heading,
                fragment: match.headingFragment(in: self),
                body: body.isEmpty ? heading : body
            )
        }
    }

    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsString = self as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: self, range: range) else {
            return nil
        }
        return nsString.substring(with: match.range(at: 1))
    }

    func snippet(matching terms: [String]) -> String {
        let plainText = plainDocumentationText
        let normalized = plainText.normalizedForDocumentationSearch
        guard let term = terms.first(where: { normalized.contains($0) }),
              let range = normalized.range(of: term)
        else {
            return String(plainText.prefix(160))
        }

        let offset = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
        let startOffset = max(0, offset - 60)
        let endOffset = min(plainText.count, offset + term.count + 100)
        let start = plainText.index(plainText.startIndex, offsetBy: startOffset)
        let end = plainText.index(plainText.startIndex, offsetBy: endOffset)
        let prefix = startOffset == 0 ? "" : "... "
        let suffix = endOffset == plainText.count ? "" : " ..."
        return prefix + String(plainText[start ..< end]) + suffix
    }
}

private extension NSTextCheckingResult {
    func headingFragment(in html: String) -> String? {
        guard let headingRange = Range(range, in: html) else {
            return nil
        }
        let tag = String(html[headingRange])
        return tag.firstMatch(for: #"id="([^"]+)""#) ??
            tag.firstMatch(for: #"name="([^"]+)""#)
    }
}

extension DocumentationViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, shouldOpenExternally(url) {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }

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

        if let url = navigationAction.request.url, shouldShowLoadingOverlay(for: url) {
            showExternalLoadingOverlay(for: url)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        if webView.url != nil {
            let url = currentDocumentationURL
            if url.bundledDocumentationURL != nil {
                setCurrentDocumentationURL(url)
            }
        }
        hideExternalLoadingOverlay()
        updateCSSVariables()
        updateNavigationButtons()
        updateButtons()
        userActivity?.needsSave = true
    }

    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        if let url = webView.url, shouldShowLoadingOverlay(for: url) {
            showExternalLoadingOverlay(for: url)
        }
        updateNavigationButtons()
        updateButtons()
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handleNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
           shouldOpenExternally(url)
        {
            openExternally(url)
            return
        }
        guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled,
              let url = externalLoadingURL ?? webView.url,
              shouldShowLoadingOverlay(for: url)
        else {
            hideExternalLoadingOverlay()
            updateNavigationButtons()
            return
        }
        showExternalLoadFailure(for: url, error: error)
        updateNavigationButtons()
    }

    private func shouldShowLoadingOverlay(for url: URL) -> Bool {
        !url.isFileURL && url.bundledDocumentationURL == nil
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        if shouldOpenAppStoreURLExternally(url) {
            return true
        }
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return !["file", "http", "https", "about"].contains(scheme)
    }

    private func shouldOpenAppStoreURLExternally(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host == "apps.apple.com" || host == "itunes.apple.com"
    }

    private func openExternally(_ url: URL) {
        webView.stopLoading()
        hideExternalLoadingOverlay()
        restoreCurrentDocumentationPage()
        updateNavigationButtons()
        UIApplication.shared.open(url)
    }

    private func restoreCurrentDocumentationPage() {
        if let localURL = lastLoadedDocumentationURL.bundledDocumentationURL {
            webView.loadFileURL(
                localURL,
                allowingReadAccessTo: localURL.localReadAccessURL
            )
        } else {
            webView.load(URLRequest(url: lastLoadedDocumentationURL))
        }
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
        let urlPathComponents = pathComponents.filter { $0 != "/" }
        return urlPathComponents.starts(with: basePathComponents)
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
