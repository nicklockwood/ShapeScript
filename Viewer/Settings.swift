//
//  Settings.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import AppKit
import CoreServices
import ModelIO

extension NSApplication {
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
}

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

final class Settings {
    static let shared = Settings()

    private var defaults = UserDefaults.standard

    // MARK: App version

    var appVersion: String? {
        get { defaults.object(forKey: #function) as? String }
        set { defaults.set(newValue, forKey: #function) }
    }

    var previousAppVersion: String? {
        get { defaults.object(forKey: #function) as? String }
        set { defaults.set(newValue, forKey: #function) }
    }

    // MARK: Welcome screen

    var showWelcomeScreenAtStartup: Bool {
        get { defaults.object(forKey: #function) as? Bool ?? true }
        set { defaults.set(newValue, forKey: #function) }
    }

    // MARK: Editor

    private(set) lazy var editorApps: [EditorApp] = {
        var appIDs = [
            "com.github.atom", "com.microsoft.VSCode",
            "com.sublimetext", "com.sublimetext.2", "com.sublimetext.3",
            "com.panic.Coda", "com.panic.Coda2",
            // Fallback option
            "com.apple.TextEdit",
        ]
        for type in fileTypes {
            guard let handlers = LSCopyAllRoleHandlersForContentType(type as CFString, .editor)?
                .takeRetainedValue() as? [String]
            else {
                continue
            }
            appIDs += handlers.filter { id in
                !blacklist.contains(where: { id.compare($0, options: .caseInsensitive) == .orderedSame })
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
        return apps.sorted()
    }()

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

    lazy var defaultEditor: EditorApp? = {
        // find best match for applicable file types
        for type in fileTypes {
            if let appID = LSCopyDefaultRoleHandlerForContentType(type as CFString, .editor)?
                .takeRetainedValue() as String?, !blacklist.contains(where: {
                    appID.compare($0, options: .caseInsensitive) == .orderedSame
                }), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)
            {
                return EditorApp(url)
            }
        }
        return editorApps.first
    }()

    func addEditorApp(for url: URL) {
        guard !editorApps.contains(where: { $0.url == url }),
              let data = bookmark(for: url)
        else {
            // TODO: Handle error
            return
        }
        editorAppBookmarks.append(data)
        editorApps.append(EditorApp(url))
        editorApps.sort()
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

    private let fileTypes = [
        "com.charcoaldesign.shapescript-source",
        "public.source-code",
        "public.plain-text",
    ]

    private let blacklist = [
        "com.apple.iWork.Numbers",
        "com.charcoaldesign.ShapeScriptMac",
    ]

    // MARK: View

    var showWireframe: Bool {
        get { defaults.object(forKey: #function) as? Bool ?? false }
        set { defaults.set(newValue, forKey: #function) }
    }

    var showAxes: Bool {
        get { defaults.object(forKey: #function) as? Bool ?? true }
        set { defaults.set(newValue, forKey: #function) }
    }
}
