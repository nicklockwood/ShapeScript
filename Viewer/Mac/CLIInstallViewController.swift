//
//  CLIInstallViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 11/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import AppKit
import ShapeScript

final class CLIInstallViewController: NSViewController {
    private static let releaseURL = URL(
        string: "https://github.com/nicklockwood/ShapeScript/releases/tag/\(ShapeScript.version)"
    )!

    // swiftformat:disable wrap
    private static let installCommand = """
    VERSION=\(ShapeScript.version) /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nicklockwood/ShapeScript/HEAD/Viewer/CLI/install.sh)"
    """
    // swiftformat:enable wrap

    private static let pathCommand = """
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
    """

    private static let verifyCommand = """
    shapescript --version
    """

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 500))

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14

        let titleLabel = NSTextField(labelWithString: "ShapeScript Command Line Tool")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let introStack = NSStackView()
        introStack.orientation = .horizontal
        introStack.alignment = .firstBaseline
        introStack.spacing = 10

        let introLabel = wrappingLabel(
            "Copy these commands into Terminal to install the ShapeScript CLI."
        )

        let terminalButton = NSButton(
            title: "Open Terminal",
            target: self,
            action: #selector(openTerminal(_:))
        )
        terminalButton.bezelStyle = .rounded

        introStack.addArrangedSubview(introLabel)
        introStack.addArrangedSubview(terminalButton)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(introStack)
        stackView.addArrangedSubview(commandSection(
            title: "Install",
            command: Self.installCommand,
            buttonTitle: "Copy Install Command",
            secondaryButton: {
                let releaseButton = NSButton(
                    title: "Manual Download...",
                    target: self,
                    action: #selector(openReleasePage(_:))
                )
                releaseButton.bezelStyle = .rounded
                return releaseButton
            }()
        ))
        stackView.addArrangedSubview(commandSection(
            title: "Add to PATH",
            command: Self.pathCommand,
            buttonTitle: "Copy PATH Command"
        ))
        stackView.addArrangedSubview(commandSection(
            title: "Check Installation",
            command: Self.verifyCommand,
            buttonTitle: "Copy Check Command"
        ))
        stackView.addArrangedSubview(docsSection())

        rootView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 50),
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -24),
            introLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])

        view = rootView
    }

    @objc private func copyCommand(_ sender: CommandButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sender.command, forType: .string)
    }

    @objc private func openReleasePage(_: Any) {
        NSWorkspace.shared.open(Self.releaseURL)
    }

    @objc private func openCLIDocs(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL.appendingPathComponent("cli"))
        view.window?.close()
    }

    @objc private func openTerminal(_: Any) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ), NSWorkspace.shared.open(terminalURL) else {
            let error = NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Terminal could not be opened.",
            ])
            NSDocumentController.shared.presentError(error)
            return
        }
    }

    private func commandSection(
        title: String,
        command: String,
        buttonTitle: String,
        secondaryButton: NSButton? = nil
    ) -> NSView {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let commandView = commandText(command)

        let copyButton = CommandButton(
            title: buttonTitle,
            target: self,
            action: #selector(copyCommand(_:)),
            command: command
        )
        copyButton.bezelStyle = .rounded

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.addArrangedSubview(copyButton)
        if let secondaryButton {
            buttonStack.addArrangedSubview(secondaryButton)
        }

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(commandView)
        stackView.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            commandView.widthAnchor.constraint(equalToConstant: 632),
        ])

        return stackView
    }

    private func docsSection() -> NSView {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6

        let titleLabel = NSTextField(labelWithString: "Next Steps")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let noteLabel = wrappingLabel(
            "See the command-line tool docs for examples of checking files, exporting models and images, and using export options."
        )
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .secondaryLabelColor

        let docsButton = NSButton(
            title: "Open CLI Docs",
            target: self,
            action: #selector(openCLIDocs(_:))
        )
        docsButton.bezelStyle = .rounded

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(noteLabel)
        stackView.addArrangedSubview(docsButton)

        NSLayoutConstraint.activate([
            noteLabel.widthAnchor.constraint(equalToConstant: 632),
        ])

        return stackView
    }

    private func commandText(_ command: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = wrappingLabel(command)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
        ])

        return container
    }

    private func wrappingLabel(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        return label
    }
}

private final class CommandButton: NSButton {
    let command: String

    init(title: String, target: AnyObject?, action: Selector?, command: String) {
        self.command = command
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
