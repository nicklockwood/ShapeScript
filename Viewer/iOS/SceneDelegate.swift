//
//  SceneDelegate.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 15/02/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

@MainActor
@objc(ShapeScriptSceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DocumentBrowserViewController(
            forOpening: [UTType(importedAs: "com.charcoaldesign.shapescript-source")]
        )
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
        self.scene(scene, openURLContexts: connectionOptions.urlContexts)
    }

    func scene(_: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        guard var inputURL = urlContexts.first?.url else {
            return
        }
        if inputURL.scheme == "shapescript" {
            var path = inputURL.absoluteString
                .deletingPrefix("shapescript:")
                .deletingPrefix("//")

            path = (path.removingPercentEncoding ?? path)
                .deletingPrefix("file://")

            if let url = URL(string: path), url.scheme ?? "file" != "file" {
                inputURL = url
            } else {
                inputURL = URL(fileURLWithPath: path)
            }
        }

        guard let documentBrowserViewController = window?
            .rootViewController as? DocumentBrowserViewController else { return }

        // Ensure the URL is a file URL
        guard inputURL.isFileURL else {
            documentBrowserViewController.presentError(
                "Could not open '\(inputURL.absoluteString)'",
                onOK: {}
            )
            return
        }

        // Reveal / import the document at the URL
        documentBrowserViewController.revealDocument(at: inputURL, importIfNeeded: true) { revealedDocumentURL, error in
            if let error {
                documentBrowserViewController.presentError(
                    "Could not open file '\(inputURL.path)'. \(error.localizedDescription)",
                    onOK: {}
                )
                return
            }

            // TODO: why is this needed?
            let revealedDocumentURL = revealedDocumentURL ?? inputURL

            // Present the Document View Controller for the revealed URL
            documentBrowserViewController.presentDocument(at: revealedDocumentURL)
        }
    }
}

private extension String {
    func deletingPrefix(_ string: String) -> String {
        if hasPrefix(string) {
            return String(dropFirst(string.count))
        }
        return self
    }
}
