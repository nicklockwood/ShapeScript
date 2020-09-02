//
//  Utilities.swift
//  Viewer
//
//  Created by Nick Lockwood on 22/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import AppKit
import Euclid

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

extension Double {
    var shortDescription: String {
        return self < 0.0001 ? "0" : String(format: "%.4g", self)
    }
}

extension Vector {
    var shortDescription: String {
        return "\(x.shortDescription) \(y.shortDescription) \(z.shortDescription)"
    }
}

extension Rotation {
    var shortDescription: String {
        return "\((roll / .pi).shortDescription) \((yaw / .pi).shortDescription) \((pitch / .pi).shortDescription)"
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
