//
//  ConsoleViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 28/06/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import UIKit

@MainActor
final class ConsoleViewController: UIViewController {
    private let textView = UITextView()
    private let log = NSMutableAttributedString()
    private var logLength = 0
    private let consoleFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private let sheetTopInset: CGFloat = 12
    private var didSelectDefaultDetent = false
    private var needsInitialDetentSelection = false
    private var appliedDetentHeights = [CGFloat]()
    private var savedDetentHeight: CGFloat?

    var consoleView: UIView {
        textView
    }

    override func loadView() {
        view = textView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTextView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 16, *) {
            updateSheetDetents(selectInitialDetent: true)
        }
        hideDimmingView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if #available(iOS 16, *) {
            updateSheetDetents()
        }
        hideDimmingView()
    }

    func clearLog() {
        logLength = 0
        log.mutableString.setString("")
        textView.text = ""
        didSelectDefaultDetent = false
        needsInitialDetentSelection = false
        appliedDetentHeights = []
        savedDetentHeight = nil
    }

    func appendLog(_ text: String) {
        let logLimit = 20000
        let remaining = logLimit - logLength
        if text.isEmpty || remaining <= 0 {
            return
        }
        var text = text
        if logLength > 0 {
            text = "\n\(text)"
        }
        var truncated = false
        if remaining < text.count {
            truncated = true
            text = text.prefix(remaining) + "... "
        }
        logLength += text.count
        log.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: UIColor.label,
                .font: consoleFont,
            ]
        ))
        if truncated {
            log.append(NSAttributedString(
                string: "Console limit exceeded. No further logs will be printed.",
                attributes: [
                    .foregroundColor: UIColor.red,
                    .font: consoleFont,
                ]
            ))
        }
        textView.attributedText = log
        let location = log.length
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 16, *) {
                updateSheetDetents()
            }
            textView.scrollRangeToVisible(NSRange(location: location, length: 1))
        }
    }

    func inlineHeight(maximumHeight: CGFloat) -> CGFloat {
        min(maximumHeight, textView.contentSize.height)
    }

    func configureSheetPresentation(delegate: UIAdaptivePresentationControllerDelegate?) {
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
        presentationController?.delegate = delegate
        needsInitialDetentSelection = true
        appliedDetentHeights = []
        if #available(iOS 16, *) {
            configureSheetAppearance()
        }
    }

    func didPresentAsSheet() {
        if #available(iOS 16, *) {
            updateSheetDetents(selectInitialDetent: true)
        }
        hideDimmingView()
    }

    func preserveDetent() {
        if #available(iOS 16, *) {
            savedDetentHeight = selectedDetentHeight
        }
    }

    @available(iOS 16, *)
    private func updateSheetDetents(selectInitialDetent: Bool = false) {
        guard let sheet = sheetPresentationController else {
            return
        }

        let maximumHeight = contentHeight(maximum: screenHeight)
        let detentHeights = detentHeights(from: minimumHeight, to: maximumHeight)
        let selectedIdentifier = sheet.selectedDetentIdentifier
        let selectedIndex = selectedIdentifier.map(detentIndex(for:))
        let largestIdentifier = detentIdentifier(for: detentHeights.count - 1)
        let newSelectedIdentifier: UISheetPresentationController.Detent.Identifier
        if shouldSelectDefaultDetent(
            selectInitialDetent: selectInitialDetent || needsInitialDetentSelection,
            selectedIndex: selectedIndex,
            detentCount: detentHeights.count
        ) {
            let targetHeight = savedDetentHeight ?? min(maximumHeight, screenHeight / 4)
            let index = nearestDetentIndex(to: targetHeight, in: detentHeights)
            newSelectedIdentifier = detentIdentifier(for: index)
            didSelectDefaultDetent = detentHeights.count > 1
        } else if let selectedIndex,
                  detentHeights.indices.contains(selectedIndex)
        {
            newSelectedIdentifier = detentIdentifier(for: selectedIndex)
        } else {
            newSelectedIdentifier = largestIdentifier
        }

        if detentHeights != appliedDetentHeights {
            sheet.detents = detentHeights.enumerated().map { index, height in
                let identifier = detentIdentifier(for: index)
                return .custom(identifier: identifier) { context in
                    min(height, context.maximumDetentValue)
                }
            }
            appliedDetentHeights = detentHeights
        }
        sheet.selectedDetentIdentifier = newSelectedIdentifier
        configureSheetAppearance(largestUndimmedDetentIdentifier: largestIdentifier)
        needsInitialDetentSelection = false
        DispatchQueue.main.async { [weak self] in
            self?.hideDimmingView()
        }
    }

    @available(iOS 16, *)
    private func configureSheetAppearance(
        largestUndimmedDetentIdentifier: UISheetPresentationController.Detent.Identifier? = nil
    ) {
        guard let sheet = sheetPresentationController else {
            return
        }
        sheet.largestUndimmedDetentIdentifier = largestUndimmedDetentIdentifier
        sheet.sourceView = nil
        if #available(iOS 17, *) {
            sheet.prefersPageSizing = true
        }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = false
    }

    private func shouldSelectDefaultDetent(
        selectInitialDetent: Bool,
        selectedIndex: Int?,
        detentCount: Int
    ) -> Bool {
        guard detentCount > 1 else {
            return false
        }
        return selectInitialDetent || !didSelectDefaultDetent || selectedIndex == nil
    }

    @available(iOS 16, *)
    private func detentHeights(from minimumHeight: CGFloat, to maximumHeight: CGFloat) -> [CGFloat] {
        let maximumHeight = max(maximumHeight, minimumHeight)
        let distance = maximumHeight - minimumHeight
        guard distance > 0 else {
            return [minimumHeight]
        }

        let intervalCount = max(1, Int((distance / 40).rounded()))
        let spacing = distance / CGFloat(intervalCount)
        return (0 ... intervalCount).map {
            minimumHeight + CGFloat($0) * spacing
        }
    }

    @available(iOS 16, *)
    private func nearestDetentIndex(to height: CGFloat, in detentHeights: [CGFloat]) -> Int {
        detentHeights.indices.min {
            abs(detentHeights[$0] - height) < abs(detentHeights[$1] - height)
        } ?? 0
    }

    @available(iOS 16, *)
    private var selectedDetentHeight: CGFloat? {
        guard let identifier = sheetPresentationController?.selectedDetentIdentifier else {
            return nil
        }
        let index = detentIndex(for: identifier)
        guard appliedDetentHeights.indices.contains(index) else {
            return nil
        }
        return appliedDetentHeights[index]
    }

    @available(iOS 16, *)
    private func detentIdentifier(for index: Int) -> UISheetPresentationController.Detent.Identifier {
        .init("console-\(index)")
    }

    @available(iOS 16, *)
    private func detentIndex(
        for identifier: UISheetPresentationController.Detent.Identifier
    ) -> Int {
        Int(identifier.rawValue.replacingOccurrences(of: "console-", with: "")) ?? -1
    }

    private var screenHeight: CGFloat {
        view.window?.screen.bounds.height ?? UIScreen.main.bounds.height
    }

    private func hideDimmingView() {
        guard let containerView = presentationController?.containerView else {
            return
        }
        hideDimmingViews(in: containerView)
    }

    private func hideDimmingViews(in view: UIView) {
        for subview in view.subviews {
            let className = String(describing: type(of: subview))
            if className.localizedCaseInsensitiveContains("dimming") {
                subview.alpha = 0
                subview.isUserInteractionEnabled = false
            }
            hideDimmingViews(in: subview)
        }
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = false
        textView.backgroundColor = .systemBackground
        textView.font = consoleFont
        textView.contentInset = UIEdgeInsets(
            top: sheetTopInset,
            left: 0,
            bottom: 8,
            right: 0
        )
        textView.scrollIndicatorInsets = UIEdgeInsets(
            top: sheetTopInset,
            left: 0,
            bottom: 8,
            right: 6
        )
        textView.textContainerInset = UIEdgeInsets(
            top: 16,
            left: 12,
            bottom: 16,
            right: 12
        )
    }

    private var minimumHeight: CGFloat {
        ceil(textView.contentInset.top +
            textView.contentInset.bottom +
            consoleFont.lineHeight +
            textView.textContainerInset.top +
            textView.textContainerInset.bottom)
    }

    private func contentHeight(maximum maximumHeight: CGFloat) -> CGFloat {
        let width = max(textView.bounds.width, view.bounds.width)
        guard width > 0 else {
            return minimumHeight
        }
        let targetSize = CGSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        var contentHeight = textView.sizeThatFits(targetSize).height
        if log.string.hasSuffix("\n") {
            contentHeight -= consoleFont.lineHeight
        }
        let height = textView.contentInset.top +
            textView.contentInset.bottom +
            contentHeight
        return min(max(height, minimumHeight), maximumHeight)
    }
}
