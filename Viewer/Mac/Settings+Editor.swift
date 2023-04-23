//
//  Settings+Editor.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 09/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import AppKit

struct EditorApp: Comparable {
    var name: String
    var url: URL

    init(_ url: URL) {
        self.url = url
        name = url.deletingPathExtension().lastPathComponent
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
        var appIDs = [
            "com.github.atom", "com.microsoft.VSCode",
            "com.sublimetext", "com.sublimetext.2", "com.sublimetext.3",
            "com.panic.Coda", "com.panic.Coda2",
            // Fallback option
            "com.apple.TextEdit",
        ]
        for type in Settings.fileTypes {
            guard let handlers = LSCopyAllRoleHandlersForContentType(type as CFString, .editor)?
                .takeRetainedValue() as? [String]
            else {
                continue
            }
            appIDs += handlers.filter { id in
                !Settings.blacklist.contains(where: {
                    id.compare($0, options: .caseInsensitive) == .orderedSame
                })
            }
        }
        var apps = [EditorApp]()
        for url in appIDs.flatMap({ id -> [URL] in
            LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?
                .takeRetainedValue() as? [URL] ?? []
        }) + editorAppBookmarks.compactMap(url(forBookmark:)) {
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
            if let appID = LSCopyDefaultRoleHandlerForContentType(type as CFString, .editor)?
                .takeRetainedValue() as String?, !Settings.blacklist.contains(where: {
                    appID.compare($0, options: .caseInsensitive) == .orderedSame
                }), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)
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

    private static let fileTypes = [
        "com.charcoaldesign.shapescript-source",
        "public.source-code",
        "public.plain-text",
    ]

    private static let blacklist = [
        "com.apple.iWork.Numbers",
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.charcoaldesign.ShapeScriptMac",
        "com.charcoaldesign.ShapeScriptViewer",
        "com.charcoaldesign.ShapeScript",
    ]
}
