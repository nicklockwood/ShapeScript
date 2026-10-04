//
//  ProgressView.swift
//  Viewer
//
//  Created by Nick Lockwood on 31/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if os(macOS)
import AppKit

private typealias OSLoadingIndicator = NSProgressIndicator
private let progressViewSize: CGFloat = 24

private extension NSProgressIndicator {
    func startAnimating() { startAnimation(nil) }
    func stopAnimating() { stopAnimation(nil) }
}

private extension OSView {
    var alpha: CGFloat {
        get { alphaValue }
        set { alphaValue = newValue }
    }
}
#elseif os(iOS)
import UIKit

private typealias OSLoadingIndicator = UIActivityIndicatorView
private let progressViewSize: CGFloat = 22
#endif

import ShapeScript

@MainActor
final class ProgressView: OSView {
    var isActive = false {
        didSet { updateProgress() }
    }

    var progress: Double? {
        didSet { updateProgress() }
    }

    var color: OSColor = {
        #if os(macOS)
        .controlAccentColor
        #else
        .label
        #endif
    }() {
        didSet {
            updateColors()
        }
    }

    private let loadingIndicator: OSLoadingIndicator = .init()
    private let progressIndicator: CircularProgressView = .init()
    private var lastProgress: Double?
    private var stallTask: Task<Void, Never>?
    private var isShowingStalledSpinner = false
    private var transitionTask: Task<Void, Never>?
    private var visibilityTask: Task<Void, Never>?

    /// Roughly one point of travel around the progress arc
    private let visibleProgressThreshold = 1.0 / (.pi * progressViewSize)

    private var animationDuration: TimeInterval {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.4
        #else
        UIAccessibility.isReduceMotionEnabled ? 0 : 0.4
        #endif
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension ProgressView {
    func updateColors() {
        progressIndicator.color = color
        #if os(macOS)
        let isLight = (color.usingColorSpace(.deviceGray)?.whiteComponent ?? 0) > 0.5
        loadingIndicator.appearance = NSAppearance(named: isLight ? .darkAqua : .aqua)
        #else
        loadingIndicator.color = color
        #endif
    }

    func configureView() {
        isHidden = true

        #if os(macOS)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        alphaValue = 0
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = true
        loadingIndicator.usesThreadedAnimation = true
        #else
        loadingIndicator.hidesWhenStopped = false
        #endif
        loadingIndicator.alpha = 0
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        updateColors()
        progressIndicator.alpha = 0
        addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: progressViewSize),
            heightAnchor.constraint(equalToConstant: progressViewSize),
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: topAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateProgress() {
        guard isActive else {
            stallTask?.cancel()
            stallTask = nil
            transitionTask?.cancel()
            transitionTask = nil
            isShowingStalledSpinner = false
            lastProgress = nil
            setVisible(false)
            return
        }

        setVisible(true)
        let progress = progress ?? progressIndicator.minValue

        updateStallState(for: progress)
        if isShowingStalledSpinner {
            loadingIndicator.startAnimating()
        }
        transitionIndicators(showProgress: true, showSpinner: isShowingStalledSpinner)
        setProgressIndicatorValue(progress, animated: true)
    }

    func setVisible(_ visible: Bool) {
        visibilityTask?.cancel()
        visibilityTask = nil
        if visible {
            isHidden = false
        }
        setContainerAlpha(visible ? 1 : 0)
        guard !visible else { return }
        visibilityTask = delayedTask(after: animationDuration) { view in
            guard !view.isActive else { return }
            view.loadingIndicator.stopAnimating()
            view.isHidden = true
        }
    }

    func transitionIndicators(showProgress: Bool, showSpinner: Bool) {
        transitionTask?.cancel()
        transitionTask = nil
        setIndicatorVisibility(showProgress: showProgress, showSpinner: showSpinner)
        guard !showSpinner else { return }
        transitionTask = delayedTask(after: animationDuration) { view in
            guard view.isActive, !view.isShowingStalledSpinner else { return }
            view.loadingIndicator.stopAnimating()
        }
    }

    func updateStallState(for progress: Double) {
        guard progress < progressIndicator.maxValue else {
            stallTask?.cancel()
            stallTask = nil
            isShowingStalledSpinner = false
            lastProgress = progress
            return
        }
        guard lastProgress.map({
            abs(progress - $0) >= visibleProgressThreshold
        }) ?? true else {
            return
        }

        lastProgress = progress
        isShowingStalledSpinner = false
        stallTask?.cancel()
        stallTask = delayedTask(after: 5) { view in
            guard view.isActive,
                  view.progress.map({
                      abs($0 - progress) < view.visibleProgressThreshold
                  }) == true
            else {
                return
            }
            view.isShowingStalledSpinner = true
            view.loadingIndicator.startAnimating()
            view.transitionIndicators(showProgress: true, showSpinner: true)
        }
    }

    func delayedTask(
        after delay: TimeInterval,
        perform action: @escaping @MainActor @Sendable (ProgressView) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action(self)
        }
    }

    func setProgressIndicatorValue(_ value: Double, animated: Bool) {
        let value = min(
            max(value, progressIndicator.minValue),
            progressIndicator.maxValue
        )
        guard animated, !isHidden, value > progressIndicator.minValue else {
            progressIndicator.setDoubleValue(value, animated: false)
            return
        }
        progressIndicator.setDoubleValue(value, animated: true)
    }

    func setContainerAlpha(_ alpha: CGFloat) {
        #if os(macOS)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = alpha
        }
        #else
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = alpha
        }
        #endif
    }

    func setIndicatorVisibility(showProgress: Bool, showSpinner: Bool) {
        #if os(macOS)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if animationDuration > 0 {
                loadingIndicator.animator().alphaValue = showSpinner ? 1 : 0
                progressIndicator.animator().alphaValue = showProgress ? 1 : 0
            } else {
                loadingIndicator.alphaValue = showSpinner ? 1 : 0
                progressIndicator.alphaValue = showProgress ? 1 : 0
            }
        }
        #else
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.loadingIndicator.alpha = showSpinner ? 1 : 0
            self.loadingIndicator.transform = showProgress && showSpinner ?
                CGAffineTransform(scaleX: 0.7, y: 0.7) : .identity
            self.progressIndicator.alpha = showProgress ? 1 : 0
        }
        #endif
    }
}
