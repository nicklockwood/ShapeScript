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

// MARK: Types

typealias OSColor = NSColor
typealias OSFont = NSFont
typealias OSButton = NSButton
typealias OSTextView = NSTextView

// MARK: General

let onlineHelpURL = URL(string: "https://shapescript.info/\(ShapeScript.version)/mac/")!

@MainActor func loadRTF(_ file: String) -> NSAttributedString {
    let file = Bundle.main.url(forResource: file, withExtension: "rtf")!
    let data = try! Data(contentsOf: file)
    return NSAttributedString(rtf: data, documentAttributes: nil)!
}

@MainActor func makeRTFTextView() -> NSTextView {
    let textView = NSTextView(frame: .zero)
    textView.isEditable = false
    textView.importsGraphics = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.drawsBackground = false
    return textView
}

@MainActor func makeScrollView(
    for textView: NSTextView,
    documentSize: NSSize
) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.contentView.drawsBackground = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 15, bottom: 15, right: 15)
    textView.frame = NSRect(origin: .zero, size: documentSize)
    textView.minSize = NSSize(width: 0, height: documentSize.height)
    textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.containerSize = NSSize(
        width: documentSize.width,
        height: CGFloat.greatestFiniteMagnitude
    )
    scrollView.documentView = textView
    return scrollView
}

@MainActor func showSheet(
    _ alert: NSAlert,
    in window: NSWindow?,
    _ handler: ((NSApplication.ModalResponse) -> Void)? = nil
) {
    if let window {
        alert.beginSheetModal(for: window, completionHandler: handler)
    } else {
        let response = alert.runModal()
        handler?(response)
    }
}

@MainActor func showSheet(
    _ dialog: NSSavePanel,
    in window: NSWindow?,
    _ handler: @escaping (NSApplication.ModalResponse) -> Void
) {
    if let window {
        dialog.beginSheetModal(for: window, completionHandler: handler)
    } else {
        let response = dialog.runModal()
        handler(response)
    }
}

@MainActor func showNewDocumentPanel() {
    let dialog = NSSavePanel()
    dialog.title = "New Document"
    dialog.showsHiddenFiles = true
    dialog.allowedFileTypes = ["shape"]
    dialog.nameFieldStringValue = "Untitled.shape"
    dialog.begin { response in
        guard response == .OK, let url = dialog.url else {
            return
        }
        do {
            let data: Data
            if let templateURL = Bundle.main.url(
                forResource: "Untitled",
                withExtension: "shape"
            ) {
                data = try Data(contentsOf: templateURL)
            } else {
                data = Data()
            }
            try data.write(to: url, options: .atomic)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    NSDocumentController.shared.presentError(error)
                }
            }
        } catch {
            NSDocumentController.shared.presentError(error)
        }
    }
}

@MainActor func dismissOpenSavePanel() {
    for window in NSApp.windows where window is NSSavePanel {
        window.close()
    }
}

// MARK: Editor selection

@MainActor func configureEditorPopup(_ popup: NSPopUpButton) {
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

@MainActor func handleEditorPopupAction(for popup: NSPopUpButton, in window: NSWindow?) {
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

// MARK: VoiceOver

@MainActor private weak var currentSpeech: NSSpeechSynthesizer?

@MainActor func voiceOver(_ string: String) {
    currentSpeech?.stopSpeaking()
    if NSWorkspace.shared.isVoiceOverEnabled,
       let speech = NSSpeechSynthesizer(voice: nil)
    {
        currentSpeech = speech
        speech.startSpeaking(string)
    }
}
