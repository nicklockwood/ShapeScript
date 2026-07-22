//
//  AppDelegate.swift
//  Viewer
//
//  Created by Nick Lockwood on 09/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa
import ShapeScript

@MainActor protocol ExportMenuProvider {
    func updateExportMenu()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow? {
        NSApp.mainWindow
    }

    lazy var welcomeWindowController: NSWindowController = makeWindowController(
        contentViewController: WelcomeViewController(),
        size: NSSize(width: 480, height: 270),
        title: nil,
        hidesTitle: true
    )

    lazy var whatsNewWindowController: NSWindowController? = makeWindowController(
        contentViewController: WhatsNewViewController(),
        size: NSSize(width: 640, height: 480),
        title: nil,
        hidesTitle: true,
        extendsContentIntoTitleBar: true
    )

    lazy var licensesWindowController: NSWindowController? = makeWindowController(
        contentViewController: LicensesViewController(),
        size: NSSize(width: 640, height: 480),
        title: nil,
        hidesTitle: true,
        extendsContentIntoTitleBar: true
    )

    lazy var preferencesWindowController: NSWindowController = makeWindowController(
        contentViewController: PreferencesViewController(),
        size: NSSize(width: 480, height: 270),
        title: "ShapeScript Preferences"
    )

    private var exampleURLs = [String: URL]()

    private var examplesMenu: NSMenu = .init()
    private var camerasMenu: NSMenu = .init()
    private(set) var exportMenuItem: NSMenuItem = .init()
    private(set) var iapMenuItem: NSMenuItem = .init()

    private var exportMenuProvider: ExportMenuProvider? {
        self as Any as? ExportMenuProvider
    }

    func applicationWillFinishLaunching(_: Notification) {
        configureMainMenu()
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

    @objc func toggleKeepInFront(_: NSMenuItem) {
        Settings.shared.keepWindowInFront.toggle()
        updateFloatingWindows(_: nil)
    }

    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSDocumentController.shared.openDocument(nil)
        }
        return false
    }

    @objc func openOnlineDocumentation(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL)
    }

    @objc func openExample(sender: NSMenuItem) {
        if let url = exampleURLs[sender.title] {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    @objc func showPreferences(sender _: NSMenuItem) {
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

    @objc func reportBug(_: Any) {
        composeEmail(
            subject: "ShapeScript bug report",
            body: "Write your bug report here.\n\nRemember to include all relevant information needed to reproduce the issue.\n\nIf you have a .shape file or screenshot that demonstrates the problem, please attach it.",
            error: "No email client is set up on this machine. Please report bugs to support@charcoaldesign.co.uk with the subject line 'ShapeScript bug report'."
        )
    }

    @objc func requestFeature(_: Any) {
        composeEmail(
            subject: "ShapeScript feature request",
            body: "Write your feature request here.",
            error: "No email client is set up on this machine. Please send feature requests to support@charcoaldesign.co.uk with the subject line 'ShapeScript feature request'."
        )
    }

    @objc func showWelcomeWindow(_: Any) {
        welcomeWindowController.showWindow(self)
    }

    @objc func showWhatsNew(_: Any) {
        whatsNewWindowController?.showWindow(self)
    }

    @objc func showLicenses(_: Any) {
        licensesWindowController?.showWindow(self)
    }
}

extension AppDelegate {
    func makeWindowController(
        contentViewController: NSViewController,
        size: NSSize,
        title: String?,
        hidesTitle: Bool = false,
        extendsContentIntoTitleBar: Bool = false
    ) -> NSWindowController {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if extendsContentIntoTitleBar {
            styleMask.insert(.fullSizeContentView)
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = title ?? ""
        window.titleVisibility = hidesTitle ? .hidden : .visible
        window.titlebarAppearsTransparent = hidesTitle && !extendsContentIntoTitleBar
        window.isMovableByWindowBackground = true
        window.contentViewController = contentViewController
        return NSWindowController(window: window)
    }

    func configureMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")

        let appMenu = NSMenu(title: "ShapeScript")
        mainMenu.addItem(menu("ShapeScript", submenu: appMenu))
        appMenu.addItem(item("About ShapeScript", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(item("Open Source Licenses", action: #selector(showLicenses(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Preferences...", action: #selector(showPreferences(sender:)), key: ",", target: self))
        iapMenuItem = item(
            "In-App Purchases...",
            action: NSSelectorFromString("openIAPWindow:"),
            target: self
        )
        iapMenuItem.isHidden = true
        appMenu.addItem(iapMenuItem)
        appMenu.addItem(.separator())
        let servicesMenu = NSMenu(title: "Services")
        appMenu.addItem(menu("Services", submenu: servicesMenu))
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide ShapeScript", action: #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(item(
            "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        ))
        appMenu.addItem(item("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit ShapeScript", action: #selector(NSApplication.terminate(_:)), key: "q"))

        let fileMenu = NSMenu(title: "File")
        mainMenu.addItem(menu("File", submenu: fileMenu))
        fileMenu.addItem(item("New...", action: #selector(NSDocumentController.newDocument(_:)), key: "n"))
        fileMenu.addItem(item("Open...", action: #selector(NSDocumentController.openDocument(_:)), key: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close", action: #selector(NSWindow.performClose(_:)), key: "w"))
        fileMenu.addItem(item("Show in Finder", action: #selector(Document.revealInFinder(_:))))
        fileMenu.addItem(.separator())
        exportMenuItem = item("Export...", action: NSSelectorFromString("export:"), key: "E")
        fileMenu.addItem(exportMenuItem)

        let editMenu = NSMenu(title: "Edit")
        mainMenu.addItem(menu("Edit", submenu: editMenu))
        editMenu.addItem(item("Undo", action: NSSelectorFromString("undo:"), key: "z"))
        editMenu.addItem(item("Redo", action: NSSelectorFromString("redo:"), key: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Open in Editor", action: #selector(Document.openInEditor(_:)), key: "e"))
        editMenu.addItem(.separator())
        editMenu.addItem(item(
            "Select Shape",
            action: #selector(Document.selectShapes(_:)),
            submenu: NSMenu(title: "Select Shape")
        ))
        editMenu.addItem(item(
            "Clear Selection",
            action: #selector(Document.clearSelection(_:))
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))

        let viewMenu = NSMenu(title: "View")
        mainMenu.addItem(menu("View", submenu: viewMenu))
        viewMenu.addItem(item(
            "Show Toolbar",
            action: #selector(NSWindow.toggleToolbarShown(_:)),
            key: "t",
            modifiers: [.command, .option]
        ))
        viewMenu.addItem(item("Customize Toolbar...", action: #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        viewMenu.addItem(.separator())
        camerasMenu = NSMenu(title: "Camera")
        camerasMenu.addItem(.separator())
        camerasMenu.addItem(item("Reset", action: #selector(DocumentViewController.resetCamera(_:)), key: "0"))
        viewMenu.addItem(item("Camera", action: #selector(selectCameras(_:)), submenu: camerasMenu))
        viewMenu.addItem(item("Orthographic", action: #selector(Document.setOrthographic(_:)), key: "O"))
        viewMenu.addItem(item("Show Wireframe", action: #selector(Document.showWireframe(_:)), key: "W"))
        viewMenu.addItem(item("Show Axes", action: #selector(Document.showAxes(_:)), key: "A"))
        viewMenu.addItem(item("Copy Camera Settings", action: #selector(Document.copyCamera(_:)), key: "C"))
        viewMenu.addItem(.separator())
        viewMenu
            .addItem(item("Model Info", action: #selector(Document.showModelInfo(_:)), key: "i"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(
            "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.command, .control]
        ))

        let windowMenu = NSMenu(title: "Window")
        mainMenu.addItem(menu("Window", submenu: windowMenu))
        windowMenu.addItem(item("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item("Zoom", action: #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Welcome Screen", action: #selector(showWelcomeWindow(_:)), target: self))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:))))
        windowMenu.addItem(item("Keep in Front", action: #selector(toggleKeepInFront(_:)), key: "F", target: self))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        mainMenu.addItem(menu("Help", submenu: helpMenu))
        helpMenu.addItem(item("ShapeScript Help", action: #selector(NSApplication.showHelp(_:)), key: "?"))
        helpMenu.addItem(item(
            "Online Documentation",
            action: #selector(openOnlineDocumentation(_:)),
            key: "0",
            modifiers: [.command, .shift],
            target: self
        ))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item("What's New in ShapeScript", action: #selector(showWhatsNew(_:)), target: self))
        examplesMenu = NSMenu(title: "Examples")
        helpMenu.addItem(menu("Examples", submenu: examplesMenu))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item("Report a Bug...", action: #selector(reportBug(_:)), target: self))
        helpMenu.addItem(item("Request a Feature...", action: #selector(requestFeature(_:)), target: self))
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private func menu(_ title: String, submenu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private func item(
        _ title: String,
        action: Selector?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        menuItem.submenu = submenu
        return menuItem
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

    @objc func selectCameras(_: NSMenuItem) {
        // Does nothing
    }
}
