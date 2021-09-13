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

func isImageFile(_ url: URL) -> Bool {
    [
        "webp",
        "png",
        "jpg", "jpeg", "jpe", "jif", "jfif", "jfi",
        "tiff", "tif",
        "psd",
        "raw", "arw", "cr2", "nrw", "k25",
        "bmp", "dib",
        "heif", "heic",
        "ind", "indd", "indt",
        "jp2", "j2k", "jpf", "jpx", "jpm", "mj2",
    ].contains(url.pathExtension.lowercased())
}

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

func showNewDocumentPanel() {
    let dialog = NSSavePanel()
    dialog.title = "New Document"
    dialog.showsHiddenFiles = true
    dialog.nameFieldStringValue = "Untitled.shape"
    dialog.begin { response in
        guard response == .OK, let url = dialog.url else {
            return
        }
        do {
            let string = """
            // ShapeScript document

            detail 32

            cube {
                position -1.5
                color 1 0 0
            }

            sphere {
                color 0 1 0
            }

            cone {
                position 1.5
                color 0 0 1
            }
            """
            try string.write(to: url, atomically: true, encoding: .utf8)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error = error {
                    NSDocumentController.shared.presentError(error)
                }
            }
        } catch {
            NSDocumentController.shared.presentError(error)
        }
    }
}

func dismissOpenSavePanel() {
    for window in NSApp.windows where window is NSSavePanel {
        window.close()
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
