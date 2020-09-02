//
//  AppDelegate.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {
    var window: NSWindow? {
        return NSApp.mainWindow
    }

    lazy var welcomeWindowController: NSWindowController = {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "WelcomeWindow") as! NSWindowController
    }()

    lazy var preferencesWindowController: NSWindowController = {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "PreferencesWindow") as! NSWindowController
    }()

    private var exampleURLs = [String: URL]()

    @IBOutlet private var examplesMenu: NSMenu!

    func applicationDidFinishLaunching(_: Notification) {
        let firstLaunchOfNewVersion = (Settings.shared.appVersion != NSApplication.appVersion)
        if firstLaunchOfNewVersion {
            Settings.shared.previousAppVersion = Settings.shared.appVersion
            Settings.shared.appVersion = NSApplication.appVersion
        }
        if WelcomeViewController.shouldShowAtStartup {
            welcomeWindowController.showWindow(self)
        }
        if let files = Bundle.main.urls(forResourcesWithExtension: "shape", subdirectory: "Examples") {
            for url in files.sorted(by: { $0.path < $1.path }) {
                let name = url.deletingPathExtension().lastPathComponent
                exampleURLs[name] = url
                examplesMenu.addItem(withTitle: name, action: #selector(openExample), keyEquivalent: "")
            }
        }
    }

    @IBAction func showHelp(_: Any) {
        NSWorkspace.shared.open(URL(string:
        "https://github.com/nicklockwood/ShapeScript/blob/master/Help/index.md")!)
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

    @IBAction func showWelcomeWindow(_: Any) {
        welcomeWindowController.showWindow(self)
    }

    @IBAction func newDocument(_: NSMenuItem) {
        let dialog = NSSavePanel()
        dialog.title = "Export Configuration"
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

    public var showWireframe = false {
        didSet {
            for case let document as Document in NSApp.orderedDocuments {
                document.updateViews()
            }
        }
    }

    @IBAction func showWireframe(_ sender: NSMenuItem) {
        showWireframe = !showWireframe
        sender.state = showWireframe ? .on : .off
    }

    // MARK: NSUserInterfaceValidations

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(showWireframe(_:)) {
            return !NSApp.orderedDocuments.isEmpty && !useOpenGL
        }
        return true
    }
}
