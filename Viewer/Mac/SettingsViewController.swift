//
//  SettingsViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@preconcurrency import Cocoa
import ShapeScript

@MainActor
final class SettingsViewController: NSViewController {
    private let editorPopUp: NSPopUpButton = .init()
    private let cacheSlider: TrackingSlider = .init()
    private let cacheValueLabel: NSTextField = .init(labelWithString: "")
    private let cacheUsageLabel: NSTextField = .init(labelWithString: "")
    private let clearCacheButton: NSButton = .init(
        title: "Clear Disk Cache",
        target: nil,
        action: nil
    )
    private var cacheUsageRequestID = 0
    private var cacheUsageUpdateScheduled = false
    private var settingsUpdatedObserver: NSObjectProtocol?
    private var geometryCacheDiskUsageObserver: NSObjectProtocol?

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 331))
        let editorLabel = makeLabel("External Editor")
        let cacheLabel = makeLabel("Disk Cache")

        editorPopUp.translatesAutoresizingMaskIntoConstraints = false
        editorPopUp.target = self
        editorPopUp.action = #selector(didSelectEditor(_:))

        cacheSlider.translatesAutoresizingMaskIntoConstraints = false
        cacheSlider.minValue = 1
        cacheSlider.maxValue = Double(Settings.diskCacheSteps.count)
        cacheSlider.numberOfTickMarks = Settings.diskCacheSteps.count
        cacheSlider.allowsTickMarkValuesOnly = true
        cacheSlider.isContinuous = true
        cacheSlider.target = self
        cacheSlider.action = #selector(didChangeCacheSize(_:))
        cacheSlider.didEndTracking = { [weak self] in
            self?.commitCacheSizeChange()
        }

        cacheValueLabel.translatesAutoresizingMaskIntoConstraints = false
        cacheValueLabel.alignment = .right
        cacheValueLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )

        cacheUsageLabel.translatesAutoresizingMaskIntoConstraints = false
        cacheUsageLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        cacheUsageLabel.textColor = .secondaryLabelColor
        cacheUsageLabel.lineBreakMode = .byTruncatingTail

        clearCacheButton.translatesAutoresizingMaskIntoConstraints = false
        clearCacheButton.target = self
        clearCacheButton.action = #selector(didClickClearCache(_:))

        rootView.addSubview(editorLabel)
        rootView.addSubview(editorPopUp)
        rootView.addSubview(cacheLabel)
        rootView.addSubview(cacheSlider)
        rootView.addSubview(cacheValueLabel)
        rootView.addSubview(cacheUsageLabel)
        rootView.addSubview(clearCacheButton)
        NSLayoutConstraint.activate([
            editorPopUp.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            editorPopUp.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            editorPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            editorPopUp.firstBaselineAnchor.constraint(equalTo: editorLabel.firstBaselineAnchor),
            editorPopUp.leadingAnchor.constraint(equalTo: editorLabel.trailingAnchor, constant: 8),
            editorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 20),
            editorLabel.widthAnchor.constraint(equalToConstant: 110),

            cacheLabel.topAnchor.constraint(equalTo: editorLabel.bottomAnchor, constant: 25),
            cacheLabel.leadingAnchor.constraint(equalTo: editorLabel.leadingAnchor),
            cacheLabel.widthAnchor.constraint(equalTo: editorLabel.widthAnchor),
            cacheSlider.centerYAnchor.constraint(equalTo: cacheLabel.centerYAnchor),
            cacheSlider.leadingAnchor.constraint(equalTo: cacheLabel.trailingAnchor, constant: 8),
            cacheValueLabel.centerYAnchor.constraint(equalTo: cacheSlider.centerYAnchor),
            cacheValueLabel.leadingAnchor.constraint(equalTo: cacheSlider.trailingAnchor, constant: 8),
            cacheValueLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            cacheValueLabel.widthAnchor.constraint(equalToConstant: 56),

            clearCacheButton.topAnchor.constraint(equalTo: cacheSlider.bottomAnchor, constant: 18),
            clearCacheButton.leadingAnchor.constraint(equalTo: cacheSlider.leadingAnchor),
            cacheUsageLabel.leadingAnchor.constraint(
                equalTo: clearCacheButton.trailingAnchor,
                constant: 16
            ),
            cacheUsageLabel.centerYAnchor.constraint(equalTo: clearCacheButton.centerYAnchor),
            cacheUsageLabel.widthAnchor.constraint(equalToConstant: 128),
            cacheUsageLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: rootView.trailingAnchor,
                constant: -20
            ),
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureEditorPopup(editorPopUp)
        updateCacheControls()
        settingsUpdatedObserver = NotificationCenter.default.addObserver(
            forName: .settingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCacheControls()
            }
        }
        geometryCacheDiskUsageObserver = NotificationCenter.default.addObserver(
            forName: .geometryCacheDiskUsageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleCacheUsageUpdate()
            }
        }
    }

    deinit {
        settingsUpdatedObserver.map(NotificationCenter.default.removeObserver)
        geometryCacheDiskUsageObserver.map(NotificationCenter.default.removeObserver)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        configureEditorPopup(editorPopUp)
        updateCacheControls()
    }

    // MARK: Editor

    @objc func didSelectEditor(_ sender: NSPopUpButton) {
        handleEditorPopupAction(for: sender, in: view.window)
    }

    // MARK: Disk cache

    @objc func didChangeCacheSize(_ sender: NSSlider) {
        let size = cacheLimit(forSliderValue: sender.integerValue)
        cacheValueLabel.stringValue = Settings.formattedCacheSize(size)
        if shouldCommitCacheSizeChangeFromSliderAction {
            commitCacheSizeChange()
        }
    }

    @objc func didClickClearCache(_: NSButton) {
        clearCacheButton.title = "Clearing…"
        clearCacheButton.isEnabled = false
        Task { @MainActor [weak self] in
            await Settings.shared.clearDiskCache()
            guard let self else {
                return
            }
            clearCacheButton.isEnabled = true
            updateCacheControls()
        }
    }

    private func updateCacheControls(refreshUsage: Bool = true) {
        let size = Settings.shared.diskCacheCapacity
        cacheSlider.integerValue = sliderValue(forCacheLimit: size)
        cacheValueLabel.stringValue = Settings.formattedCacheSize(size)
        if cacheUsageLabel.stringValue.isEmpty {
            cacheUsageLabel.stringValue = formattedCacheUsage(nil)
        }
        clearCacheButton.title = "Clear Disk Cache"
        if refreshUsage {
            updateCacheUsage(showPlaceholder: false)
        }
    }

    private func updateCacheUsage(showPlaceholder: Bool) {
        if showPlaceholder {
            cacheUsageLabel.stringValue = formattedCacheUsage(nil)
        }
        cacheUsageRequestID += 1
        let requestID = cacheUsageRequestID
        Task { @MainActor [weak self] in
            let usage = await Settings.shared.diskCacheUsage
            guard let self, requestID == cacheUsageRequestID else {
                return
            }
            setCacheUsageLabel(formattedCacheUsage(usage))
        }
    }

    private func setCacheUsageLabel(_ value: String) {
        guard cacheUsageLabel.stringValue != value else {
            return
        }
        cacheUsageLabel.stringValue = value
    }

    private func scheduleCacheUsageUpdate() {
        guard view.window != nil, !cacheUsageUpdateScheduled else {
            return
        }
        cacheUsageUpdateScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self else {
                return
            }
            cacheUsageUpdateScheduled = false
            updateCacheUsage(showPlaceholder: false)
        }
    }

    private func sliderValue(forCacheLimit size: Int) -> Int {
        (Settings.diskCacheSteps.firstIndex(of: size) ?? 0) + 1
    }

    private func cacheLimit(forSliderValue value: Int) -> Int {
        let steps = Settings.diskCacheSteps
        return steps[max(0, min(value - 1, steps.count - 1))]
    }

    private func commitCacheSizeChange() {
        let size = cacheLimit(forSliderValue: cacheSlider.integerValue)
        guard Settings.shared.diskCacheCapacity != size else {
            return
        }
        Settings.shared.diskCacheCapacity = size
    }

    private var shouldCommitCacheSizeChangeFromSliderAction: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            false
        default:
            true
        }
    }

    private func formattedCacheUsage(_ bytes: Int?) -> String {
        guard let bytes else {
            return "Stored: --"
        }
        return "Stored: \(Settings.formattedCacheUsage(bytes))"
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        return label
    }
}

@MainActor
private final class TrackingSlider: NSSlider {
    var didEndTracking: (@MainActor () -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        didEndTracking?()
    }
}
