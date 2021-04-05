//
//  Utilities.swift
//  Viewer
//
//  Created by Nick Lockwood on 22/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import AppKit
import Euclid
import ShapeScript

// MARK: General

let isHighSierra: Bool = {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return os.majorVersion == 10 && os.minorVersion == 13
}()

let useOpenGL = isHighSierra

func showSheet(_ alert: NSAlert, in window: NSWindow?,
               _ handler: ((NSApplication.ModalResponse) -> Void)? = nil)
{
    if let window = window {
        alert.beginSheetModal(for: window, completionHandler: handler)
    } else {
        let response = alert.runModal()
        handler?(response)
    }
}

func showSheet(_ dialog: NSSavePanel, in window: NSWindow?,
               _ handler: @escaping (NSApplication.ModalResponse) -> Void)
{
    if let window = window {
        dialog.beginSheetModal(for: window, completionHandler: handler)
    } else {
        let response = dialog.runModal()
        handler(response)
    }
}

// MARK: Formatting for display

protocol ShortDescribable {
    var shortDescription: String { get }
}

extension Double: ShortDescribable {
    var shortDescription: String {
        self < 0.0001 ? "0" : floor(self) == self ?
            "\(Int(self))" : String(format: "%.4g", self)
    }
}

extension Vector: ShortDescribable {
    var shortDescription: String {
        "\(x.shortDescription) \(y.shortDescription) \(z.shortDescription)"
    }
}

extension Angle: ShortDescribable {
    var shortDescription: String {
        (radians / .pi).shortDescription
    }
}

extension Rotation: ShortDescribable {
    var shortDescription: String {
        "\(roll.shortDescription) \(yaw.shortDescription) \(pitch.shortDescription)"
    }
}

extension Color: ShortDescribable {
    var shortDescription: String {
        "\(r.shortDescription) \(g.shortDescription) \(b.shortDescription) \(a.shortDescription)"
    }
}

extension Texture: ShortDescribable {
    var shortDescription: String {
        switch self {
        case let .file(name: _, url: url):
            return url.path
        case .data:
            return "texture { #data }"
        }
    }
}

extension Path: ShortDescribable {
    var shortDescription: String {
        if subpaths.count > 1 {
            return "path { subpaths: \(subpaths.count) }"
        }
        return "path { points: \(points.count) }"
    }
}

extension Geometry: ShortDescribable {
    var shortDescription: String {
        let fields = [
            name.flatMap { $0.isEmpty ? nil : "    name: \($0)" },
            children.isEmpty ? nil : "    children: \(children.count)",
            "    size: \(transform.scale.shortDescription)",
            "    position: \(transform.offset.shortDescription)",
            "    orientation: \(transform.rotation.shortDescription)",
        ].compactMap { $0 }.joined(separator: "\n")

        return """
        \(type) {
        \(fields)
        }
        """
    }
}

// MARK: Editor selection

func configureEditorPopup(_ popup: NSPopUpButton) {
    let selectedEditor = Settings.shared.selectedEditor ?? Settings.shared.defaultEditor

    popup.removeAllItems()
    for app in Settings.shared.editorApps {
        popup.addItem(withTitle: app.name)
        if app == selectedEditor {
            popup.select(popup.menu?.items.last)
        }
    }
    popup.menu?.addItem(.separator())
    popup.addItem(withTitle: "Other…")
}

func handleEditorPopupAction(for popup: NSPopUpButton, in window: NSWindow?) {
    let index = popup.indexOfSelectedItem
    if index < Settings.shared.editorApps.count {
        Settings.shared.selectedEditor = Settings.shared.editorApps[index]
        return
    }

    let appDirectory = NSSearchPathForDirectoriesInDomains(.allApplicationsDirectory, .systemDomainMask, true).first

    let dialog = NSOpenPanel()
    dialog.title = "Select App"
    dialog.showsHiddenFiles = false
    dialog.directoryURL = appDirectory.map { URL(fileURLWithPath: $0) }
    dialog.allowedFileTypes = ["app"]

    showSheet(dialog, in: window) { response in
        guard response == .OK, let url = dialog.url else {
            if let editor = Settings.shared.selectedEditor?.name {
                popup.selectItem(withTitle: editor)
            }
            return
        }
        Settings.shared.selectedEditor = EditorApp(url)
    }
}
