//
//  Utilities.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/06/2026.
//

import ShapeScript
import UIKit

// MARK: Types

typealias OSColor = UIColor
typealias OSFont = UIFont
typealias OSButton = UIButton
typealias OSTextView = UITextView

// MARK: General

let onlineHelpURL = URL(string: "https://shapescript.info/\(ShapeScript.version)/ios/")!
let editorHelpURL = onlineHelpURL.appendingPathComponent("editor-help")

@MainActor func loadRTF(_ file: String) throws -> NSAttributedString {
    let file = Bundle.main.url(forResource: file, withExtension: "rtf")!
    let data = try! Data(contentsOf: file)
    let string = try NSMutableAttributedString(data: data, documentAttributes: nil)
    let range = NSRange(location: 0, length: string.length)
    string.addAttributes([.foregroundColor: UIColor.label], range: range)
    return string
}

// MARK: VoiceOver

@MainActor func voiceOver(_: String) {
    // Not implemented
}

@available(iOS 16.0, *)
extension UINavigationItem {
    func configureDocumentTitleMenu(
        fileURL: URL?,
        renameDelegate: (any UINavigationItemRenameDelegate)?,
        activityViewControllerProvider: (() -> UIActivityViewController)? = nil,
        menuProvider: (([UIMenuElement]) -> [UIMenuElement])? = nil
    ) {
        guard let fileURL else {
            documentProperties = nil
            self.renameDelegate = nil
            titleMenuProvider = nil
            return
        }

        let documentProperties = UIDocumentProperties(url: fileURL)
        documentProperties.activityViewControllerProvider = activityViewControllerProvider
        self.documentProperties = documentProperties
        self.renameDelegate = renameDelegate
        titleMenuProvider = { suggestedActions in
            UIMenu(children: menuProvider?(suggestedActions) ?? suggestedActions)
        }
    }
}

@MainActor
extension UIApplication {
    var documentBrowserViewController: DocumentBrowserViewController? {
        connectedScenes.compactMap { scene -> DocumentBrowserViewController? in
            guard let windowScene = scene as? UIWindowScene else {
                return nil
            }
            return windowScene.windows.compactMap {
                $0.rootViewController as? DocumentBrowserViewController
            }.first
        }.first
    }
}

extension UIBarButtonItem {
    convenience init(
        image: UIImage?,
        menuTitle: String,
        handler: @escaping UIActionHandler
    ) {
        let action = UIAction(title: menuTitle, image: image, handler: handler)
        self.init(title: nil, image: image, primaryAction: action)
        accessibilityLabel = menuTitle
        if #available(iOS 16.0, *) {
            menuRepresentation = action
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if #available(iOS 16.0, *),
           let action = menuRepresentation as? UIAction
        {
            action.attributes = isEnabled ? [] : .disabled
        }
    }
}
