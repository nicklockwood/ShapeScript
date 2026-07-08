//
//  WelcomeViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 02/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

@MainActor
final class WelcomeViewController: NSViewController {
    private let textView: NSTextView = makeRTFTextView()
    private var shouldShowAtStartupCheckbox: NSButton = .init()

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 482, height: 370))

        let titleLabel = NSTextField(labelWithString: "Welcome to ShapeScript")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 25)

        let scrollView = makeScrollView(
            for: textView,
            documentSize: NSSize(width: 442, height: 197)
        )

        let guideButton = NSButton(
            title: "Getting Started Guide",
            target: self,
            action: #selector(openGettingStartedGuide(_:))
        )
        guideButton.translatesAutoresizingMaskIntoConstraints = false
        guideButton.bezelStyle = .rounded

        let checkbox = NSButton(
            checkboxWithTitle: "Show at Start",
            target: self,
            action: #selector(toggleShowAtStartup(_:))
        )
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(titleLabel)
        rootView.addSubview(scrollView)
        rootView.addSubview(guideButton)
        rootView.addSubview(checkbox)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            guideButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 26),
            guideButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),

            checkbox.topAnchor.constraint(equalTo: guideButton.bottomAnchor, constant: 30),
            checkbox.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            rootView.bottomAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 30),
        ])

        shouldShowAtStartupCheckbox = checkbox
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.textStorage?.setAttributedString(loadRTF("Welcome"))
        shouldShowAtStartupCheckbox.state =
            Settings.shared.showWelcomeScreenAtStartup ? .on : .off
    }

    @objc func openGettingStartedGuide(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL.appendingPathComponent("getting-started"))
    }

    @objc func toggleShowAtStartup(_ sender: NSButton) {
        Settings.shared.showWelcomeScreenAtStartup = (sender.state == .on)
    }
}
