//
//  SceneDelegate.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 15/02/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import ShapeScript
import UIKit
import UniformTypeIdentifiers

let mainActivityType = "com.charcoaldesign.ShapeScriptViewer.main"
let mainSceneConfigurationName = "Default Configuration"
let mainSceneTitle = "ShapeScript"
let mainURLActivityKey = "url"

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
            forOpening: [.shape, .csg]
        )
        window.backgroundColor = .clear
        #if os(visionOS)
        window.isOpaque = false
        #endif
        window.makeKeyAndVisible()
        self.window = window
        self.scene(scene, openURLContexts: connectionOptions.urlContexts)
        for activity in connectionOptions.userActivities {
            self.scene(scene, continue: activity)
        }
    }

    func stateRestorationActivity(for _: UIScene) -> NSUserActivity? {
        let activity = NSUserActivity(activityType: mainActivityType)
        activity.title = mainSceneTitle
        activity.targetContentIdentifier = mainActivityType
        return activity
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == mainActivityType,
              let string = userActivity.userInfo?[mainURLActivityKey] as? String,
              let fileURL = URL(string: string),
              let documentBrowserViewController = window?
                  .rootViewController as? DocumentBrowserViewController
        else {
            return
        }
        documentBrowserViewController.continueMainActivity(userActivity)
        if let windowScene = scene as? UIWindowScene {
            windowScene.title = fileURL.displayBaseName
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        #if os(visionOS)
        UIApplication.shared.closeAuxiliaryScenes()
        #else
        UIApplication.shared.closeAuxiliaryScenesIfNoMainScenesRemain(excluding: scene)
        #endif
    }

    func scene(_: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        guard let documentBrowserViewController = window?
            .rootViewController as? DocumentBrowserViewController else { return }

        for urlContext in urlContexts {
            documentBrowserViewController.openDocument(from: urlContext)
        }
    }
}

@MainActor
extension DocumentBrowserViewController {
    func continueMainActivity(_ userActivity: NSUserActivity) {
        guard userActivity.activityType == mainActivityType,
              let string = userActivity.userInfo?[mainURLActivityKey] as? String,
              let fileURL = URL(string: string)
        else {
            return
        }
        presentDocumentWhenReady(at: fileURL)
    }

    func openDocument(from urlContext: UIOpenURLContext) {
        var inputURL = urlContext.url
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

        // Ensure the URL is a file URL
        guard inputURL.isFileURL else {
            presentError(
                "Could not open '\(inputURL.absoluteString)'",
                onOK: {}
            )
            return
        }

        // Reveal / import the document at the URL
        revealDocument(at: inputURL, importIfNeeded: true) { revealedDocumentURL, error in
            if let error {
                self.presentError(
                    "Could not open file '\(inputURL.path)'. \(error.localizedDescription)",
                    onOK: {}
                )
                return
            }

            // TODO: why is this needed?
            let revealedDocumentURL = revealedDocumentURL ?? inputURL

            // Present the Document View Controller for the revealed URL
            self.presentDocument(at: revealedDocumentURL)
        }
    }
}

extension UIApplication {
    func closeAuxiliaryScenes() {
        closeHelpScenes()
        closeSourceScenes()
        #if os(visionOS)
        closeVolumeScenes()
        #endif
    }

    func closeAuxiliaryScenesIfNoMainScenesRemain(excluding disconnectedScene: UIScene? = nil) {
        Task { @MainActor in
            let hasDocumentScene = self.connectedScenes.contains { scene in
                guard scene !== disconnectedScene else {
                    return false
                }
                if scene.session.configuration.name == mainSceneConfigurationName {
                    return true
                }
                #if os(visionOS)
                if scene.isVolumeScene {
                    return true
                }
                #endif
                return false
            }
            guard !hasDocumentScene else {
                return
            }
            self.closeAuxiliaryScenes()
        }
    }

    #if os(visionOS)
    func closeVolumeScenes() {
        Task { @MainActor in
            let volumeSessions = self.openSessions.filter {
                $0.configuration.name == volumeSceneConfigurationName
            }
            for session in volumeSessions {
                self.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            }
        }
    }
    #endif
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
