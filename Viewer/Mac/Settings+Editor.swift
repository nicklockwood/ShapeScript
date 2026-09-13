//
//  Settings+Editor.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

struct EditorApp: Comparable {
    var name: String
    var url: URL

    init(_ url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
    }

    static func < (lhs: EditorApp, rhs: EditorApp) -> Bool {
        lhs.name < rhs.name
    }
}

extension Settings {
    // MARK: Editor

    var editorApps: [EditorApp] {
        if let apps = associatedData[#function] as? [EditorApp] {
            return apps
        }
        var appURLs = Settings.preferredEditorBundleIDs.flatMap {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0)
        }
        for type in Settings.fileTypes {
            appURLs += NSWorkspace.shared.urlsForApplications(toOpen: type).filter {
                !Settings.isBlacklisted($0)
            }
        }
        var apps = [EditorApp]()
        for url in appURLs + editorAppBookmarks.compactMap(url(forBookmark:)) {
            let app = EditorApp(url)
            if !apps.contains(where: { $0.name == app.name }) {
                apps.append(app)
            }
        }
        apps.sort()
        associatedData[#function] = apps
        return apps
    }

    var selectedEditor: EditorApp? {
        get {
            let data = defaults.object(forKey: #function) as? Data
            return data.flatMap(url(forBookmark:)).map(EditorApp.init)
        }
        set {
            let bookmark = newValue.flatMap { self.bookmark(for: $0.url) }
            defaults.set(bookmark, forKey: #function)
        }
    }

    var defaultEditor: EditorApp? {
        if let app = associatedData[#function] as? EditorApp {
            return app
        }
        // find best match for applicable file types
        for type in Settings.fileTypes {
            if let url = NSWorkspace.shared.urlForApplication(toOpen: type),
               !Settings.isBlacklisted(url)
            {
                return EditorApp(url)
            }
        }
        let app = editorApps.first
        associatedData[#function] = app
        return app
    }

    func addEditorApp(for url: URL) {
        guard !editorApps.contains(where: { $0.url == url }),
              let data = bookmark(for: url)
        else {
            // TODO: Handle error
            return
        }
        editorAppBookmarks.append(data)
        associatedData["editorApps"] = nil
    }

    var userDidChooseEditor: Bool {
        get { defaults.bool(forKey: #function) }
        set { defaults.set(newValue, forKey: #function) }
    }

    private var editorAppBookmarks: [Data] {
        get { defaults.object(forKey: #function) as? [Data] ?? [] }
        set { defaults.set(newValue, forKey: #function) }
    }

    private func bookmark(for url: URL) -> Data? {
        // TODO: Handle errors
        try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func url(forBookmark data: Data) -> URL? {
        // TODO: Handle errors
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static let fileTypes: [UTType] = [
        .shape,
        .sourceCode,
        .plainText,
    ]

    private static let preferredEditorBundleIDs = [
        "com.github.atom", "com.microsoft.VSCode",
        "com.sublimetext", "com.sublimetext.2", "com.sublimetext.3",
        "com.panic.Coda", "com.panic.Coda2",
        // Fallback option
        "com.apple.TextEdit",
    ]

    private static let blacklist = [
        "com.apple.iWork.Numbers",
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.charcoaldesign.ShapeScriptMac",
        "com.charcoaldesign.ShapeScriptViewer",
        "com.charcoaldesign.ShapeScript",
    ]

    private static func isBlacklisted(_ url: URL) -> Bool {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            return false
        }
        return blacklist.contains {
            bundleID.compare($0, options: .caseInsensitive) == .orderedSame
        }
    }
}
