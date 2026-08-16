//
//  DocumentationIndexViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import UIKit

struct DocumentationIndexItem {
    let title: String
    let indentationLevel: Int
    let url: URL?
}

private struct DocumentationIndexNode: Hashable {
    let id: Int
    let item: DocumentationIndexItem

    static func == (lhs: DocumentationIndexNode, rhs: DocumentationIndexNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
protocol DocumentationIndexViewControllerDelegate: AnyObject {
    func documentationIndexViewController(
        _ viewController: DocumentationIndexViewController,
        didSelect item: DocumentationIndexItem
    )
}

final class DocumentationIndexViewController: UIViewController, UICollectionViewDelegate {
    private enum Section {
        case main
    }

    weak var delegate: DocumentationIndexViewControllerDelegate?
    private let tree = DocumentationIndexTree(items: DocumentationIndex.loadItems())
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DocumentationIndexNode>!

    override func loadView() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout()
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        view = UIView()
        view.backgroundColor = .clear
        view.addSubview(backgroundView)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDataSource()
        applySnapshot()
    }

    func selectItem(for url: URL) {
        guard let node = tree.node(matching: url) else {
            clearSelection(animated: false)
            return
        }
        expandParents(of: node)
        select(node, animated: false)
    }

    private func select(_ node: DocumentationIndexNode, animated: Bool) {
        guard let indexPath = dataSource.indexPath(for: node) else {
            return
        }
        collectionView.selectItem(at: indexPath, animated: animated, scrollPosition: [])
    }

    private func clearSelection(animated: Bool) {
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
    }

    private func expandParents(of node: DocumentationIndexNode) {
        let parents = tree.parents(of: node)
        guard !parents.isEmpty else {
            return
        }
        var snapshot = dataSource.snapshot(for: .main)
        snapshot.expand(parents)
        dataSource.apply(snapshot, to: .main, animatingDifferences: false)
    }

    func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let node = dataSource.itemIdentifier(for: indexPath), hasChildren(node) else {
            return true
        }

        if node.item.url != nil, isExpandedAndSelected(node, at: indexPath) {
            toggle(node)
            return false
        }
        return true
    }

    private func isSelected(at indexPath: IndexPath) -> Bool {
        collectionView.indexPathsForSelectedItems?.contains(indexPath) == true
    }

    private func isExpandedAndSelected(_ node: DocumentationIndexNode, at indexPath: IndexPath) -> Bool {
        dataSource.snapshot(for: .main).isExpanded(node) && isSelected(at: indexPath)
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let node = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        if hasChildren(node), node.item.url == nil {
            toggle(node)
            clearSelection(animated: true)
            return
        }
        if hasChildren(node), !dataSource.snapshot(for: .main).isExpanded(node) {
            expand(node)
            select(node, animated: true)
        }
        if node.item.url != nil {
            delegate?.documentationIndexViewController(self, didSelect: node.item)
        }
    }

    private func hasChildren(_ node: DocumentationIndexNode) -> Bool {
        !tree.children(of: node).isEmpty
    }

    private func expand(_ node: DocumentationIndexNode) {
        var snapshot = dataSource.snapshot(for: .main)
        snapshot.expand([node])
        dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }

    private func toggle(_ node: DocumentationIndexNode) {
        var snapshot = dataSource.snapshot(for: .main)
        if snapshot.isExpanded(node) {
            snapshot.collapse([node])
        } else {
            snapshot.expand([node])
        }
        dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
        configuration.backgroundColor = .clear
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<
            UICollectionViewListCell,
            DocumentationIndexNode
        > { [weak self] cell, _, node in
            var content = UIListContentConfiguration.sidebarCell()
            content.text = node.item.title
            content.textProperties.numberOfLines = 2
            content.textProperties.color = .label
            cell.contentConfiguration = content
            cell.accessories = self?.tree.children(of: node).isEmpty == false ? [
                .outlineDisclosure(options: .init(tintColor: .secondaryLabel)),
            ] : []
        }

        dataSource = UICollectionViewDiffableDataSource<Section, DocumentationIndexNode>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: item
            )
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, DocumentationIndexNode>()
        snapshot.appendSections([.main])
        dataSource.apply(snapshot, animatingDifferences: false)

        var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<DocumentationIndexNode>()
        sectionSnapshot.append(tree.roots)
        for root in tree.roots {
            appendDescendants(of: root, to: &sectionSnapshot)
        }
        dataSource.apply(sectionSnapshot, to: .main, animatingDifferences: false)
    }

    private func appendDescendants(
        of node: DocumentationIndexNode,
        to snapshot: inout NSDiffableDataSourceSectionSnapshot<DocumentationIndexNode>
    ) {
        let children = tree.children(of: node)
        guard !children.isEmpty else {
            return
        }
        snapshot.append(children, to: node)
        for child in children {
            appendDescendants(of: child, to: &snapshot)
        }
    }
}

private struct DocumentationIndexTree {
    let roots: [DocumentationIndexNode]
    private let childrenByNode: [DocumentationIndexNode: [DocumentationIndexNode]]
    private let parentsByNode: [DocumentationIndexNode: DocumentationIndexNode]
    private let nodesByURL: [URL: DocumentationIndexNode]

    init(items: [DocumentationIndexItem]) {
        var roots: [DocumentationIndexNode] = []
        var childrenByNode: [DocumentationIndexNode: [DocumentationIndexNode]] = [:]
        var parentsByNode: [DocumentationIndexNode: DocumentationIndexNode] = [:]
        var nodesByURL: [URL: DocumentationIndexNode] = [:]
        var stack: [DocumentationIndexNode] = []
        for item in items.enumerated().map({ DocumentationIndexNode(id: $0.offset, item: $0.element) }) {
            while let last = stack.last,
                  last.item.indentationLevel >= item.item.indentationLevel
            {
                stack.removeLast()
            }
            if let parent = stack.last {
                childrenByNode[parent, default: []].append(item)
                parentsByNode[item] = parent
            } else {
                roots.append(item)
            }
            if let url = item.item.url {
                nodesByURL[url] = item
            }
            stack.append(item)
        }
        self.roots = roots
        self.childrenByNode = childrenByNode
        self.parentsByNode = parentsByNode
        self.nodesByURL = nodesByURL
    }

    func children(of node: DocumentationIndexNode) -> [DocumentationIndexNode] {
        childrenByNode[node] ?? []
    }

    func node(matching url: URL) -> DocumentationIndexNode? {
        nodesByURL[url]
    }

    func parents(of node: DocumentationIndexNode) -> [DocumentationIndexNode] {
        var parents = [DocumentationIndexNode]()
        var child = node
        while let parent = parentsByNode[child] {
            parents.insert(parent, at: 0)
            child = parent
        }
        return parents
    }
}

private enum DocumentationIndex {
    static func loadItems() -> [DocumentationIndexItem] {
        guard let url = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Documentation"
        ),
            let html = try? String(contentsOf: url)
        else {
            return []
        }
        return parseItems(in: html, relativeTo: url)
    }

    private static func parseItems(in html: String, relativeTo indexURL: URL) -> [DocumentationIndexItem] {
        var depth = 0
        return html
            .components(separatedBy: .newlines)
            .flatMap { line -> [DocumentationIndexItem] in
                var items: [DocumentationIndexItem] = []
                let lineDepth = depth
                items.append(contentsOf: linkItems(in: line, depth: lineDepth, relativeTo: indexURL))
                depth += line.matchCount(for: #"<ul\b"#)
                depth -= line.matchCount(for: #"</ul>"#)
                depth = max(0, depth)
                return items
            }
    }

    private static func linkItems(
        in line: String,
        depth: Int,
        relativeTo indexURL: URL
    ) -> [DocumentationIndexItem] {
        if let heading = headingItem(in: line, depth: depth) {
            return [heading]
        }
        guard let regex = try? NSRegularExpression(pattern: #"<a href="([^"]+)">(.+?)</a>"#) else {
            return []
        }
        let nsString = line as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return regex.matches(in: line, range: range).compactMap { match in
            let path = nsString.substring(with: match.range(at: 1))
            let title = nsString.substring(with: match.range(at: 2)).plainDocumentationText
            guard !title.isEmpty, let url = documentationURL(for: path, relativeTo: indexURL) else {
                return nil
            }
            return DocumentationIndexItem(
                title: title,
                indentationLevel: max(0, depth - 1),
                url: url
            )
        }
    }

    private static func headingItem(in line: String, depth: Int) -> DocumentationIndexItem? {
        guard !line.contains("<a "),
              let title = line.firstMatch(for: #"<li><p>(.*?)</p>"#)?.plainDocumentationText,
              !title.isEmpty
        else {
            return nil
        }
        return DocumentationIndexItem(
            title: title,
            indentationLevel: max(0, depth - 1),
            url: nil
        )
    }

    private static func documentationURL(for path: String, relativeTo indexURL: URL) -> URL? {
        guard let components = URLComponents(string: path) else {
            return nil
        }
        let filePath = components.path
        guard !filePath.isEmpty else {
            return nil
        }
        var url = indexURL.deletingLastPathComponent().appendingPathComponent(filePath)
        if let fragment = components.fragment,
           var fileComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            fileComponents.fragment = fragment
            url = fileComponents.url ?? url
        }
        return url
    }
}
