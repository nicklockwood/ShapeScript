//
//  ContextMenuInteraction.swift
//  ContextMenu
//
//  Created by Nick Lockwood on 29/06/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import UIKit

@MainActor
public final class ContextMenuInteraction: NSObject, UIInteraction {
    public struct Configuration {
        public enum PresentationStyle {
            case automatic
            case editMenu
        }

        public var menu: UIMenu
        public var presentationStyle: PresentationStyle

        public init(
            menu: UIMenu,
            presentationStyle: PresentationStyle = .automatic
        ) {
            self.menu = menu
            self.presentationStyle = presentationStyle
        }
    }

    public typealias MenuProvider = (_ location: CGPoint) -> Configuration?

    private let menuProvider: MenuProvider
    private weak var attachedView: UIView?
    private var longPressGesture: UILongPressGestureRecognizer?
    private var editMenuInteraction: AnyObject?
    private weak var menuButton: ContextMenuButton?

    public var view: UIView? {
        attachedView
    }

    public init(menuProvider: @escaping MenuProvider) {
        self.menuProvider = menuProvider
        super.init()
    }

    public func willMove(to view: UIView?) {
        if view == nil {
            cleanupButton()
            if let longPressGesture {
                attachedView?.removeGestureRecognizer(longPressGesture)
            }
            longPressGesture = nil
            if #available(iOS 16, *),
               let interaction = editMenuInteraction as? UIEditMenuInteraction
            {
                attachedView?.removeInteraction(interaction)
                editMenuInteraction = nil
            }
            attachedView = nil
        }
    }

    public func didMove(to view: UIView?) {
        guard let view else {
            return
        }
        attachedView = view

        if runningOnMac, #available(iOS 16, *) {
            _ = editMenuInteraction(for: view)
        }

        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        view.addGestureRecognizer(gesture)
        longPressGesture = gesture
    }

    @objc private func handleLongPress(_ gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .began,
              let view = attachedView
        else {
            return
        }

        let location = gestureRecognizer.location(in: view)
        presentMenu(at: location)
    }

    public func presentMenu(at location: CGPoint) {
        guard let view = attachedView,
              let configuration = menuProvider(location)
        else {
            return
        }

        cleanupButton()

        if #available(iOS 17.4, *), !runningOnMac, configuration.presentationStyle == .automatic {
            presentContextMenu(configuration.menu, at: location, in: view)
        } else if #available(iOS 16, *) {
            presentEditMenu(at: location, in: view)
        }
    }

    private var runningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    @available(iOS 17.4, *)
    private func presentContextMenu(_ menu: UIMenu, at location: CGPoint, in view: UIView) {
        let button = ContextMenuButton(type: .custom)
        button.frame = CGRect(origin: location, size: CGSize(width: 1, height: 1))
        button.alpha = 0.01
        button.isAccessibilityElement = false
        button.showsMenuAsPrimaryAction = true
        button.menu = menu
        button.preferredMenuElementOrder = .fixed
        button.onMenuDismiss = { [weak self, weak button] in
            guard self?.menuButton === button else {
                return
            }
            self?.cleanupButton()
        }
        view.addSubview(button)
        menuButton = button
        DispatchQueue.main.async {
            button.performPrimaryAction()
        }
    }

    private func cleanupButton() {
        menuButton?.removeFromSuperview()
        menuButton = nil
    }
}

#if compiler(>=6.2)
@available(iOS 16, *)
extension ContextMenuInteraction: @MainActor UIEditMenuInteractionDelegate {}
#else
@MainActor
@available(iOS 16, *)
extension ContextMenuInteraction: UIEditMenuInteractionDelegate {}
#endif

@available(iOS 16, *)
extension ContextMenuInteraction {
    public func editMenuInteraction(
        _: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions _: [UIMenuElement]
    ) -> UIMenu? {
        menuProvider(configuration.sourcePoint)?.menu
    }

    private func presentEditMenu(at location: CGPoint, in view: UIView) {
        let configuration = UIEditMenuConfiguration(
            identifier: nil,
            sourcePoint: location
        )
        editMenuInteraction(for: view).presentEditMenu(with: configuration)
    }

    private func editMenuInteraction(for view: UIView) -> UIEditMenuInteraction {
        if let interaction = editMenuInteraction as? UIEditMenuInteraction {
            return interaction
        }
        let interaction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        editMenuInteraction = interaction
        return interaction
    }
}

private final class ContextMenuButton: UIButton {
    var onMenuDismiss: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(
            interaction,
            willEndFor: configuration,
            animator: animator
        )

        if let animator {
            animator.addCompletion { [weak self] in
                self?.onMenuDismiss?()
            }
        } else {
            onMenuDismiss?()
        }
    }
}
