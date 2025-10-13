//
//  AppDelegate.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa
import ShapeScript

protocol ExportMenuProvider {
    func updateExportMenu()
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow? {
        NSApp.mainWindow
    }

    lazy var welcomeWindowController: NSWindowController = NSStoryboard(name: "Main", bundle: nil)
        .instantiateController(withIdentifier: "WelcomeWindow") as! NSWindowController

    lazy var whatsNewWindowController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil)
        .instantiateController(withIdentifier: "ReleaseNotesWindow") as? NSWindowController

    lazy var licensesWindowController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil)
        .instantiateController(withIdentifier: "LicensesWindow") as? NSWindowController

    lazy var preferencesWindowController: NSWindowController = NSStoryboard(name: "Main", bundle: nil)
        .instantiateController(withIdentifier: "PreferencesWindow") as! NSWindowController

    private var exampleURLs = [String: URL]()

    @IBOutlet private var examplesMenu: NSMenu!
    @IBOutlet private var camerasMenu: NSMenu!
    @IBOutlet var exportMenuItem: NSMenuItem?
    @IBOutlet var iapMenuItem: NSMenuItem?

    private var exportMenuProvider: ExportMenuProvider? {
        self as Any as? ExportMenuProvider
    }

    func applicationDidFinishLaunching(_: Notification) {
        let firstLaunchOfNewVersion = (Settings.shared.appVersion != appVersion)
        if firstLaunchOfNewVersion {
            Settings.shared.previousAppVersion = Settings.shared.appVersion
            Settings.shared.appVersion = appVersion
        }
        if Settings.shared.showWelcomeScreenAtStartup {
            welcomeWindowController.showWindow(self)
            dismissOpenSavePanel()
        } else if firstLaunchOfNewVersion {
            whatsNewWindowController?.showWindow(self)
            dismissOpenSavePanel()
        }
        if let files = Bundle.main.urls(forResourcesWithExtension: "shape", subdirectory: "Examples") {
            for url in files.sorted(by: { $0.path < $1.path }) {
                let name = url.deletingPathExtension().lastPathComponent
                exampleURLs[name] = url
                examplesMenu.addItem(withTitle: name, action: #selector(openExample), keyEquivalent: "")
            }
        }
        exportMenuProvider?.updateExportMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateFloatingWindows),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_: Notification) {
        updateFloatingWindows(nil)
    }

    @objc private func updateFloatingWindows(_: Notification?) {
        guard NSApp.mainWindow != nil else {
            return
        }
        for window in documentWindows {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = Bundle.main.bundleIdentifier ?? "ShapeScript"
            if window == NSApp.mainWindow, Settings.shared.keepWindowInFront {
                if window.level != .floating {
                    window.level = .floating
                }
            } else if window.level == .floating {
                window.level = .normal
            }
        }
    }

    private var documentWindows: [NSWindow] {
        NSDocumentController.shared.documents.flatMap {
            $0.windowControllers.compactMap(\.window)
        }
    }

    @IBAction func toggleKeepInFront(_: NSMenuItem) {
        Settings.shared.keepWindowInFront.toggle()
        updateFloatingWindows(_: nil)
    }

    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSDocumentController.shared.openDocument(nil)
        }
        return false
    }

    @IBAction func openOnlineDocumentation(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL)
    }

    @IBAction func openExample(sender: NSMenuItem) {
        if let url = exampleURLs[sender.title] {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    @IBAction func showPreferences(sender _: NSMenuItem) {
        preferencesWindowController.showWindow(self)
    }

    private func composeEmail(subject: String, body: String, error: String) {
        let emailService = NSSharingService(named: .composeEmail)!
        emailService.recipients = ["support@charcoaldesign.co.uk"]
        emailService.subject = subject

        if emailService.canPerform(withItems: [body]) {
            emailService.perform(withItems: [body])
        } else {
            let error = NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: error,
            ])
            NSDocumentController.shared.presentError(error)
        }
    }

    @IBAction func reportBug(_: Any) {
        composeEmail(
            subject: "ShapeScript bug report",
            body: "Write your bug report here.\n\nRemember to include all relevant information needed to reproduce the issue.\n\nIf you have a .shape file or screenshot that demonstrates the problem, please attach it.",
            error: "No email client is set up on this machine. Please report bugs to support@charcoaldesign.co.uk with the subject line 'ShapeScript bug report'."
        )
    }

    @IBAction func requestFeature(_: Any) {
        composeEmail(
            subject: "ShapeScript feature request",
            body: "Write your feature request here.",
            error: "No email client is set up on this machine. Please send feature requests to support@charcoaldesign.co.uk with the subject line 'ShapeScript feature request'."
        )
    }

    @IBAction func showWelcomeWindow(_: Any) {
        welcomeWindowController.showWindow(self)
    }

    @IBAction func showWhatsNew(_: Any) {
        whatsNewWindowController?.showWindow(self)
    }

    @IBAction func showLicenses(_: Any) {
        licensesWindowController?.showWindow(self)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectCameras(_:)):
            menuItem.title = "Camera"
            return false
        case #selector(AppDelegate.toggleKeepInFront(_:)):
            menuItem.state = Settings.shared.keepWindowInFront ? .on : .off
            return true
        default:
            return true
        }
    }

    @IBAction func selectCameras(_: NSMenuItem) {
        // Does nothing
    }
}
