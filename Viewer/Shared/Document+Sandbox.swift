//
//  Document+Sandbox.swift
//  Viewer
//
//  Created by Nick Lockwood on 20/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

extension Document {
    func clearBookmarks() {
        UserDefaults.standard.removeObject(forKey: "SandboxBookmarks")
    }

    var bookmarks: [String: Data] {
        set {
            UserDefaults.standard.set(newValue, forKey: "SandboxBookmarks")
        }
        get {
            UserDefaults.standard.dictionary(forKey: "SandboxBookmarks") as? [String: Data] ?? [:]
        }
    }

    func bookmarkURL(_ url: URL) {
        _ = accessSecurityScopedURL(url)
        // Create an app-scoped bookmark for the selected file or folder
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarks[url.absoluteString] = data
        }
    }

    func accessSecurityScopedURL(_ resolvedURL: URL) -> Bool {
        if securityScopedResources.contains(resolvedURL) {
            return true
        } else if resolvedURL.startAccessingSecurityScopedResource() {
            securityScopedResources.insert(resolvedURL)
            return true
        }
        return false
    }

    func resolveBookMark(for url: URL) -> URL? {
        let path = url.absoluteString
        guard let data = bookmarks[path] else {
            guard !url.pathExtension.isEmpty,
                  let directoryURL = resolveBookMark(for: url.deletingLastPathComponent())
            else {
                return nil
            }
            let resolvedURL = directoryURL.appendingPathComponent(url.lastPathComponent)
            return accessSecurityScopedURL(resolvedURL) ? resolvedURL : nil
        }
        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), accessSecurityScopedURL(resolvedURL) else {
            return nil
        }
        if isStale {
            bookmarkURL(resolvedURL)
        }
        return resolvedURL
    }
}
