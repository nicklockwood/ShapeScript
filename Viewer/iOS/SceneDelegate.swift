//
//  SceneDelegate.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 15/02/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

let mainActivityType = "com.charcoaldesign.ShapeScriptViewer.main"
let mainSceneConfigurationName = "Default Configuration"
let mainSceneTitle = "ShapeScript"

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
        windowScene.title = mainSceneTitle

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DocumentBrowserViewController(
            forOpening: [UTType(importedAs: "com.charcoaldesign.shapescript-source")]
        )
        window.backgroundColor = .clear
        window.makeKeyAndVisible()
        self.window = window
        self.scene(scene, openURLContexts: connectionOptions.urlContexts)
    }

    func stateRestorationActivity(for _: UIScene) -> NSUserActivity? {
        let activity = NSUserActivity(activityType: mainActivityType)
        activity.title = mainSceneTitle
        activity.targetContentIdentifier = mainActivityType
        return activity
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        UIApplication.shared.closeAuxiliaryScenesIfNoMainScenesRemain(excluding: scene)
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

extension UIApplication {
    func closeAuxiliaryScenesIfNoMainScenesRemain(excluding disconnectedScene: UIScene? = nil) {
        Task { @MainActor in
            let hasMainScene = self.connectedScenes.contains { scene in
                scene !== disconnectedScene &&
                    scene.session.configuration.name == mainSceneConfigurationName
            }
            guard !hasMainScene else {
                return
            }
            self.closeHelpScenes()
            self.closeSourceScenes()
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

extension UIWindowScene {
    var shouldRequestSceneActivation: Bool {
        #if os(visionOS)
        true
        #else
        activationState != .foregroundActive
        #endif
    }

    var appearsFullscreen: Bool {
        #if os(visionOS)
        return false
        #else
        let sceneSize = coordinateSpace.bounds.standardized.size
        let screenSize = screen.coordinateSpace.bounds.standardized.size
        let sceneArea = sceneSize.width * sceneSize.height
        let screenArea = screenSize.width * screenSize.height
        return screenArea > 0 && sceneArea / screenArea >= 0.9
        #endif
    }
}
