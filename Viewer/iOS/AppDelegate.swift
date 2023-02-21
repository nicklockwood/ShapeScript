//
//  AppDelegate.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window?.backgroundColor = .black
        return true
    }

    func application(_: UIApplication, open inputURL: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        var inputURL = inputURL
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

        guard let documentBrowserViewController = window?.rootViewController as? DocumentBrowserViewController else { return false }

        // Ensure the URL is a file URL
        guard inputURL.isFileURL else {
            documentBrowserViewController.presentError(
                "Could not open '\(inputURL.absoluteString)'",
                onOK: {}
            )
            return false
        }

        // Reveal / import the document at the URL
        documentBrowserViewController.revealDocument(at: inputURL, importIfNeeded: true) { revealedDocumentURL, error in
            if let error = error {
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

        return true
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
