//
//  ExampleApp.swift
//  ContextMenuExample
//
//  Created by Nick Lockwood on 11/07/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import ContextMenu
import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private var runningOnMac: Bool {
    #if targetEnvironment(macCatalyst)
    true
    #else
    ProcessInfo.processInfo.isiOSAppOnMac
    #endif
}

private var contextMenuGestureName: String {
    runningOnMac ? "Right-click" : "Long press"
}

struct ContentView: View {
    @State private var color = UIColor.systemTeal
    @State private var symbolName = "doc.text.image"
    @State private var copiedText = "\(contextMenuGestureName) anywhere on the content"

    var body: some View {
        TabView {
            ForEach(MenuDemoMode.allCases) { mode in
                MenuDemoScreen(
                    mode: mode,
                    color: color,
                    symbolName: symbolName,
                    copiedText: copiedText,
                    onColorChange: { color = $0 },
                    onSymbolChange: { symbolName = $0 },
                    onCopy: { copiedText = "Copied from location \(Int($0.x)), \(Int($0.y))" }
                )
                .tabItem {
                    Label(mode.title, systemImage: mode.systemImage)
                }
            }
        }
    }
}

private enum MenuDemoMode: CaseIterable, Identifiable {
    case contextMenu
    case editMenu
    case anchoredMenu

    var id: Self { self }

    var title: String {
        switch self {
        case .contextMenu:
            "UIContextMenu"
        case .editMenu:
            "UIEditMenu"
        case .anchoredMenu:
            "ContextMenu"
        }
    }

    var systemImage: String {
        switch self {
        case .contextMenu:
            "rectangle.on.rectangle"
        case .editMenu:
            "text.cursor"
        case .anchoredMenu:
            "mappin.and.ellipse"
        }
    }

    var detail: String {
        if runningOnMac {
            switch self {
            case .contextMenu:
                "Uses UIContextMenuInteraction."
            case .editMenu:
                "Uses UIEditMenuInteraction."
            case .anchoredMenu:
                "Uses ContextMenuInteraction."
            }
        } else {
            switch self {
            case .contextMenu:
                "Uses UIContextMenuInteraction directly. The delegate receives the press location, but UIKit presents a context menu for the view."
            case .editMenu:
                "Uses UIEditMenuInteraction directly. It presents from a source point, using the edit-menu presentation style."
            case .anchoredMenu:
                "Uses ContextMenuInteraction. On iOS 17.4 and later it opens a dropdown-style menu at the press location."
            }
        }
    }
}

private struct MenuDemoScreen: View {
    let mode: MenuDemoMode
    let color: UIColor
    let symbolName: String
    let copiedText: String
    let onColorChange: (UIColor) -> Void
    let onSymbolChange: (String) -> Void
    let onCopy: (CGPoint) -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                MenuDemoContent(
                    mode: mode,
                    color: color,
                    symbolName: symbolName,
                    copiedText: copiedText,
                    onColorChange: onColorChange,
                    onSymbolChange: onSymbolChange,
                    onCopy: onCopy
                )
                .frame(maxWidth: 420)

                Text(mode.detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(24)
        }
    }
}

private struct MenuDemoContent: UIViewRepresentable {
    let mode: MenuDemoMode
    let color: UIColor
    let symbolName: String
    let copiedText: String
    let onColorChange: (UIColor) -> Void
    let onSymbolChange: (String) -> Void
    let onCopy: (CGPoint) -> Void

    func makeUIView(context: Context) -> ContentCardView {
        let view = ContentCardView()
        context.coordinator.attach(mode: mode, to: view)
        return view
    }

    func updateUIView(_ view: ContentCardView, context: Context) {
        context.coordinator.parent = self
        view.configure(color: color, symbolName: symbolName, detail: copiedText)
        if mode == .editMenu, #unavailable(iOS 16) {
            view.configureUnsupportedMode()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: MenuDemoContent
        private weak var cardView: ContentCardView?
        private var editMenuInteraction: AnyObject?

        init(parent: MenuDemoContent) {
            self.parent = parent
        }

        func attach(mode: MenuDemoMode, to view: ContentCardView) {
            cardView = view

            switch mode {
            case .contextMenu:
                view.addInteraction(UIContextMenuInteraction(delegate: self))
            case .editMenu:
                guard #available(iOS 16, *) else {
                    view.configureUnsupportedMode()
                    return
                }

                let interaction = UIEditMenuInteraction(delegate: self)
                view.addInteraction(interaction)
                editMenuInteraction = interaction

                let gesture = UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(handleEditMenuLongPress(_:))
                )
                view.addGestureRecognizer(gesture)
            case .anchoredMenu:
                view.addInteraction(ContextMenuInteraction { [weak self] location in
                    guard let self else {
                        return nil
                    }
                    return ContextMenuInteraction.Configuration(menu: menu(at: location))
                })
            }
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                self?.menu(at: location)
            }
        }

        @objc private func handleEditMenuLongPress(_ gestureRecognizer: UIGestureRecognizer) {
            guard gestureRecognizer.state == .began,
                  let view = cardView
            else {
                return
            }

            if #available(iOS 16, *),
               let interaction = editMenuInteraction as? UIEditMenuInteraction
            {
                let configuration = UIEditMenuConfiguration(
                    identifier: nil,
                    sourcePoint: gestureRecognizer.location(in: view)
                )
                interaction.presentEditMenu(with: configuration)
            }
        }

        private func menu(at location: CGPoint) -> UIMenu {
            UIMenu(children: [
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [parent] _ in
                    parent.onCopy(location)
                },
                UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), children: [
                    UIAction(title: "Teal", image: UIImage(systemName: "circle.fill")) { [parent] _ in
                        parent.onColorChange(.systemTeal)
                    },
                    UIAction(title: "Indigo", image: UIImage(systemName: "circle.fill")) { [parent] _ in
                        parent.onColorChange(.systemIndigo)
                    },
                    UIAction(title: "Green", image: UIImage(systemName: "circle.fill")) { [parent] _ in
                        parent.onColorChange(.systemGreen)
                    },
                ]),
                UIMenu(title: "Symbol", image: UIImage(systemName: "sparkles"), children: [
                    UIAction(title: "Document", image: UIImage(systemName: "doc.text.image")) { [parent] _ in
                        parent.onSymbolChange("doc.text.image")
                    },
                    UIAction(title: "Photo", image: UIImage(systemName: "photo")) { [parent] _ in
                        parent.onSymbolChange("photo")
                    },
                    UIAction(title: "Folder", image: UIImage(systemName: "folder")) { [parent] _ in
                        parent.onSymbolChange("folder")
                    },
                ]),
            ])
        }
    }
}

final class ContentCardView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let hintLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(color: UIColor, symbolName: String, detail: String) {
        backgroundColor = color
        imageView.image = UIImage(systemName: symbolName)
        detailLabel.text = detail
        hintLabel.text = "\(contextMenuGestureName) anywhere"
    }

    func configureUnsupportedMode() {
        hintLabel.text = "Requires iOS 16 or later"
    }

    private func setup() {
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 10)

        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit

        titleLabel.text = "Content Preview"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center

        hintLabel.text = "\(contextMenuGestureName) anywhere"
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, detailLabel, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -36),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }
}

@available(iOS 16, *)
extension MenuDemoContent.Coordinator: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions _: [UIMenuElement]
    ) -> UIMenu? {
        menu(at: configuration.sourcePoint)
    }
}
