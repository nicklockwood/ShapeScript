//
//  AppDelegate.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa
import ShapeScript

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow? {
        NSApp.mainWindow
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
    @IBOutlet private var showWireframeMenuItem: NSMenuItem!
    @IBOutlet private var showAxesMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_: Notification) {
        let firstLaunchOfNewVersion = (Settings.shared.appVersion != NSApplication.appVersion)
        if firstLaunchOfNewVersion {
            Settings.shared.previousAppVersion = Settings.shared.appVersion
            Settings.shared.appVersion = NSApplication.appVersion
        }
        if WelcomeViewController.shouldShowAtStartup {
            welcomeWindowController.showWindow(self)
            dismissOpenSavePanel()
        }
        if let files = Bundle.main.urls(forResourcesWithExtension: "shape", subdirectory: "Examples") {
            for url in files.sorted(by: { $0.path < $1.path }) {
                let name = url.deletingPathExtension().lastPathComponent
                exampleURLs[name] = url
                examplesMenu.addItem(withTitle: name, action: #selector(openExample), keyEquivalent: "")
            }
        }
        showWireframe = Settings.shared.showWireframe
        showAxes = Settings.shared.showAxes
    }

    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSDocumentController.shared.openDocument(nil)
        }
        return false
    }

    @IBAction func showHelp(_: Any) {
        let path: String
        if let version = Bundle(for: ShapeScript.Scene.self)
            .object(forInfoDictionaryKey: "CFBundleShortVersionString")
        {
            path = "\(version)/Help/index.md"
        } else {
            path = "master/Help/index.md"
        }
        NSWorkspace.shared.open(URL(string:
            "https://github.com/nicklockwood/ShapeScript/blob/\(path)")!)
    }

    @IBAction func openExample(sender: NSMenuItem) {
        if let url = exampleURLs[sender.title] {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    @IBAction func showPreferences(sender _: NSMenuItem) {
        preferencesWindowController.showWindow(self)
    }

    @IBAction func showWelcomeWindow(_: Any) {
        welcomeWindowController.showWindow(self)
    }

    public var showWireframe = false {
        didSet {
            Settings.shared.showWireframe = showWireframe
            showWireframeMenuItem.state = showWireframe ? .on : .off
            for case let document as Document in NSApp.orderedDocuments {
                document.rerender()
            }
        }
    }

    @IBAction func showWireframe(_: NSMenuItem) {
        showWireframe = !showWireframe
    }

    public var showAxes = true {
        didSet {
            Settings.shared.showAxes = showAxes
            showAxesMenuItem.state = showAxes ? .on : .off
            for case let document as Document in NSApp.orderedDocuments {
                document.updateViews()
            }
        }
    }

    @IBAction func showAxes(_ sender: NSMenuItem) {
        showAxes = !showAxes
        sender.state = showAxes ? .on : .off
    }
}
