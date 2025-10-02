//
//  TextView.swift
//  Subtext
//
//  Created by Nick Lockwood on 22/01/2022.
//

import UIKit

@objc protocol TextViewDelegate: UITextViewDelegate {
    @objc optional func textView(
        _ textView: TextView,
        replacementForText text: String
    ) -> String
}

class TextView: UIScrollView {
    private let layoutManager: LayoutManager
    private let gutterView = LineNumberView()
    private var lineCount = 0
    private var lastSpaceIndex: Int?
    private var updateLock: Int = 0
    private var lastInsertedTextAndRange: (text: String, range: NSRange)?
    fileprivate var currentAction: TextAction?
    let textView: UITextView

    private var _contentInset: UIEdgeInsets = .zero
    override var contentInset: UIEdgeInsets {
        get { _contentInset }
        set {
            _contentInset = newValue
            setNeedsLayout()
        }
    }

    override var undoManager: UndoManager? {
        textView.undoManager
    }

    var showLineNumbers: Bool = false {
        didSet {
            guard showLineNumbers != oldValue else { return }
            updateLineCount()
            setNeedsLayout()
        }
    }

    var wrapLines: Bool = false {
        didSet { setNeedsLayout() }
    }

    var indentNewLines: Bool = true

    var showInvisibleCharacters: Bool = false {
        didSet {
            layoutManager.invalidateDisplay(forCharacterRange: NSRange(
                location: 0,
                length: textView.textStorage.length
            ))
            setNeedsLayout()
        }
    }

    var spellCheckingType: UITextSpellCheckingType = .no {
        didSet {
            textView.spellCheckingType = spellCheckingType
            // Workaround for spellcheck mode not updating
            textView.reloadInputViews()
        }
    }

    var disableAutocorrection: Bool = true {
        didSet { updateAutocorrectOptions() }
    }

    var disableDoubleSpacePeriodShortcut: Bool = false

    var text: String {
        get { textView.text }
        set {
            guard newValue != textView.text else { return }
            textView.text = newValue
            updateLineCount()
            previousSize = .zero
            setNeedsLayout()
        }
    }

    var selectedRange: NSRange {
        get { textView.selectedRange }
        set { textView.selectedRange = newValue }
    }

    var font: UIFont = .monospacedSystemFont(ofSize: 15, weight: .regular) {
        didSet { updateFont() }
    }

    var textColor: UIColor = .label {
        didSet { textView.textColor = textColor }
    }

    var isEditable: Bool = true {
        didSet { textView.isEditable = isEditable }
    }

    override var isFirstResponder: Bool {
        textView.isFirstResponder
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    override init(frame: CGRect) {
        self.layoutManager = LayoutManager()
        self.textView = TextView.textView(with: layoutManager)
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.layoutManager = LayoutManager()
        self.textView = TextView.textView(with: layoutManager)
        super.init(coder: coder)
        setUp()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setUp() {
        layoutManager.delegate = self
        contentInsetAdjustmentBehavior = .never
        super.contentInset = .zero
        isDirectionalLockEnabled = true
        showsHorizontalScrollIndicator = true
        textView.font = UIFontMetrics.default.scaledFont(for: font)
        textView.textColor = textColor
        textView.adjustsFontForContentSizeCategory = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = false
        #if !os(visionOS)
        textView.keyboardDismissMode = .interactive
        #endif
        textView.spellCheckingType = spellCheckingType
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.isEditable = isEditable
        textView.frame = bounds
        textView.delegate = self
        textView.textDragDelegate = self
        textView.textDropDelegate = self
        updateAutocorrectOptions()
        addSubview(textView)
        gutterView.font = UIFontMetrics.default.scaledFont(for: font)
        gutterView.backgroundColor = textView.backgroundColor
        gutterView.contentMode = .right
        gutterView.isHidden = true
        addSubview(gutterView)
        avoidKeyboard()
        updateLineCount()
        updateInsets()

        if #available(iOS 16.0, *) {
            textView.isFindInteractionEnabled = true
        }
    }

    private func updateAutocorrectOptions() {
        textView.autocorrectionType = disableAutocorrection ? .no : .default
        textView.autocapitalizationType = disableAutocorrection ? .none : .sentences
    }

    private var previousSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        updateLineNumbers()
        updateInsets()
        let size = frame.size
        let width = wrapLines ? size.width : .greatestFiniteMagnitude
        if width != previousSize.width || size.height != previousSize.height {
            previousSize.width = width
            previousSize.height = size.height
            let oldOffset = textView.contentOffset
            textView.sizeToFitWidth(width, in: size)
            textView.contentOffset = oldOffset
            if contentSize != textView.frame.size {
                contentSize = textView.frame.size
            }
            let textView = textView
            DispatchQueue.main.async {
                let maxY = max(0, textView.contentSize.height - textView.frame.height
                    + textView.contentInset.bottom)
                if textView.contentOffset.y > maxY {
                    textView.contentOffset.y = maxY
                }
            }
        }
        showsHorizontalScrollIndicator = !wrapLines
        if _contentInset.bottom > safeAreaInsets.bottom {
            horizontalScrollIndicatorInsets.left =
                textView.contentInset.left - safeAreaInsets.left
            horizontalScrollIndicatorInsets.right =
                textView.contentInset.right - safeAreaInsets.right
            horizontalScrollIndicatorInsets.bottom = _contentInset.bottom
        } else {
            horizontalScrollIndicatorInsets.left =
                max(textView.contentInset.left, safeAreaInsets.bottom) - safeAreaInsets.left
            horizontalScrollIndicatorInsets.right =
                max(safeAreaInsets.right, safeAreaInsets.bottom) - safeAreaInsets.right
            horizontalScrollIndicatorInsets.bottom = -safeAreaInsets.bottom
        }
        textView.verticalScrollIndicatorInsets.bottom = max(
            _contentInset.bottom,
            safeAreaInsets.bottom
        )
        textView.verticalScrollIndicatorInsets.right = textView.frame.width
            - frame.width - contentOffset.x - safeAreaInsets.left
        updateLineNumbers()
        updateInsets()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        gutterView.font = UIFontMetrics.default.scaledFont(for: font)
        setNeedsLayout()
    }
}

private extension TextView {
    static func textView(with layoutManager: LayoutManager) -> UITextView {
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        return _UITextView(frame: .zero, textContainer: textContainer)
    }

    func updateFont() {
        textView.font = UIFontMetrics.default.scaledFont(for: font)
        gutterView.font = UIFontMetrics.default.scaledFont(for: font)
        setNeedsLayout()
    }

    func updateInsets() {
        var inset = UIEdgeInsets(
            top: _contentInset.top + safeAreaInsets.top,
            left: _contentInset.left + safeAreaInsets.left,
            bottom: _contentInset.bottom + safeAreaInsets.bottom,
            right: _contentInset.right + safeAreaInsets.right
        )
        layoutManager.font = UIFontMetrics.default.scaledFont(for: font)
        layoutManager.drawInvisibleChars = showInvisibleCharacters
        if showLineNumbers {
            layoutManager.gutterWidth = ceil(String(lineCount).size(withAttributes: [
                .font: UIFontMetrics.default.scaledFont(for: font),
            ]).width + 8)
            inset.left = max(inset.left + layoutManager.gutterWidth - 10, layoutManager.gutterWidth)
            gutterView.isHidden = false
            gutterView.frame.origin.x = contentOffset.x
            gutterView.frame.size = CGSize(
                width: inset.left,
                height: frame.height
            )
        } else {
            gutterView.isHidden = true
            gutterView.frame.size.width = 0
        }
        if inset != textView.contentInset {
            textView.contentInset = inset
            if textView.contentOffset.y == 0 {
                textView.contentOffset.y = -inset.top
            }
        }
    }

    func updateLineCount() {
        guard showLineNumbers else {
            return
        }
        let lineCount = text.lineCount
        if lineCount != self.lineCount {
            self.lineCount = lineCount
            setNeedsLayout()
        }
    }
}

private extension String {
    var lineCount: Int {
        reduce(1) { $0 + ("\r\n\n\r".contains($1) ? 1 : 0) }
    }

    func startOfLine(at index: String.Index) -> String.Index {
        assert(index <= endIndex)
        var index = index
        while index > startIndex {
            let prev = self.index(before: index)
            if self[prev].isNewline {
                return index
            }
            index = prev
        }
        return index
    }

    func indentForLine(at index: Int) -> String {
        let endIndex = min(.init(utf16Offset: index, in: self), endIndex)
        var index = startOfLine(at: endIndex)
        var indent = ""
        while index < endIndex, case let char = self[index],
              char.isWhitespace, !char.isNewline
        {
            indent.append(char)
            index = self.index(after: index)
        }
        return indent
    }
}

private enum TextAction {
    case typing, delete, cut, paste, drag, drop
}

private final class _UITextView: UITextView {
    var textView: TextView? {
        delegate as! TextView?
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(selectAll(_:)):
            return true
        case #selector(captureTextFromCamera(_:)):
            return false // weird and broken
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    override func cut(_ sender: Any?) {
        textView?.currentAction = .cut
        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        textView?.currentAction = .paste
        super.paste(sender)
    }

    override func captureTextFromCamera(_ sender: Any?) {
        if #available(iOS 15, *) {
            super.captureTextFromCamera(sender)
        }
    }

    override func replace(_ range: UITextRange, withText text: String) {
        super.replace(range, withText: text)
        // TODO: optimize this by using `updateLineCount(oldText:newText:)` instead
        textView?.updateLineCount()
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard let textView = superview as? TextView, !textView.wrapLines else {
            return rect
        }
        // workaround for wrong value when caret is offscreen
        let offset = min(
            textStorage.mutableString.length,
            offset(from: beginningOfDocument, to: position)
        )
        let newlineRange = textStorage.mutableString.rangeOfCharacter(
            from: .newlines,
            options: .backwards,
            range: NSRange(location: 0, length: offset)
        )
        let lineStart = newlineRange.location == NSNotFound ? 0 : newlineRange.upperBound
        let line = textStorage.mutableString.substring(
            with: NSRange(location: lineStart, length: offset - lineStart)
        )
        let x = max(rect.origin.x, (line as NSString).size(
            withAttributes: font.map { [.font: $0] } ?? [:]
        ).width)
        rect.origin.x = x.isFinite ? x : 0
        return rect
    }
}

extension UITextView {
    func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(
            from: beginningOfDocument,
            offset: range.location
        ), let end = position(
            from: start,
            offset: range.length
        ) else {
            return nil
        }
        return textRange(from: start, to: end)
    }
}

private extension UITextView {
    func sizeToFitWidth(_ width: CGFloat, in bounds: CGSize) {
        let newWidth = sizeThatFits(CGSize(
            width: width - contentInset.left - contentInset.right,
            height: CGFloat.greatestFiniteMagnitude
        )).width + contentInset.left + contentInset.right
        let newSize = CGSize(
            width: max(newWidth, bounds.width),
            height: bounds.height
        )
        if newSize != frame.size {
            frame.size = newSize
            DispatchQueue.main.async {
                self.contentOffset.x = -self.contentInset.left
            }
        }
    }
}

extension TextView: UITextViewDelegate, UIScrollViewDelegate {
    private var textViewDelegate: TextViewDelegate? {
        delegate as? TextViewDelegate
    }

    private var uiTextViewDelegate: UITextViewDelegate? {
        delegate as? UITextViewDelegate
    }

    func textViewDidChange(_ textView: UITextView) {
        if currentAction == nil {
            // Check for period insertion
            if disableDoubleSpacePeriodShortcut,
               let lastSpaceIndex,
               textView.textStorage.mutableString
               .character(at: lastSpaceIndex) == ".".utf16.first
            {
                textView.textStorage.mutableString.replaceCharacters(in: NSRange(
                    location: lastSpaceIndex,
                    length: 1
                ), with: " ")
            }
            // Content was not pre-processed, so need to update everything
            if let newText = textViewDelegate?.textView?(
                self,
                replacementForText: text
            ), newText != text {
                DispatchQueue.main.async { self.text = newText }
                return
            } else {
                updateLineCount()
            }
        } else {
            // Clean up object replacement characters left after dictation
            let range = NSRange(location: 0, length: textView.textStorage.length)
            textView.textStorage.mutableString.replaceOccurrences(
                of: "\u{fffc}",
                with: "",
                range: range
            )
        }
        currentAction = nil
        textViewDelegate?.textViewDidChange?(textView)
        if !wrapLines {
            previousSize = .zero
            setNeedsLayout()
        }
    }

    func textViewDidChangeSelection(_: UITextView) {
        // Scroll to caret position
        if !wrapLines, let range = textView.selectedTextRange?.start {
            var caretRect = convert(textView.caretRect(for: range), from: textView)
            caretRect = caretRect.insetBy(dx: -40, dy: 0) // allow breathing room
            caretRect.origin.x = max(0, caretRect.minX)
            if caretRect.minX < bounds.minX {
                setContentOffset(CGPoint(x: caretRect.minX, y: contentOffset.y), animated: true)
            } else if caretRect.maxX > bounds.maxX {
                let offset = contentOffset.x + (caretRect.maxX - bounds.maxX)
                setContentOffset(CGPoint(x: offset, y: contentOffset.y), animated: true)
            }
        }
    }

    private func replace(_ range: NSRange, with text: String, for action: String) {
        let oldText = textView.textStorage.mutableString.substring(with: range)
        let newRange = NSRange(location: range.location, length: text.utf16.count)
        textView.undoManager?.beginUndoGrouping()
        textView.undoManager?.registerUndo(withTarget: self) {
            $0.replace(newRange, with: oldText, for: action)
        }
        textView.undoManager?.setActionName(action)
        if textView.textStorage.mutableString.length == 0, let font = textView.font {
            // Prevent font being reset
            textView.textStorage.setAttributedString(.init(
                string: text, attributes: [.font: font, .foregroundColor: textColor]
            ))
        } else {
            textView.textStorage.mutableString.replaceCharacters(in: range, with: text)
        }
        assert(textView.textStorage.mutableString.substring(with: newRange) == text)
        updateLock += 1
        textView.selectedRange = NSRange(location: newRange.upperBound, length: 0)
        updateLock -= 1
        if showLineNumbers {
            updateLineCount(oldText: oldText, newText: text)
        }
        textViewDidChange(textView)
        textView.undoManager?.endUndoGrouping()
        // Workaround for double insertion bug
        lastInsertedTextAndRange = (text, range)
    }

    private func updateLineCount(oldText: String, newText: String) {
        let count = newText.lineCount - oldText.lineCount
        if count != 0 {
            lineCount += count
            setNeedsLayout()
        }
    }

    private func fixRange(_ range: NSRange) -> NSRange {
        // Avoid splitting Windows (CRLF) linebreaks
        var range = range
        let string = textView.textStorage.mutableString
        if range.location > 0, range.location < string.length,
           string.character(at: range.location) == 10,
           string.character(at: range.location - 1) == 13
        {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        } else if range.length == 1, range.location < string.length - 1,
                  string.character(at: range.location) == 13,
                  string.character(at: range.location + 1) == 10
        {
            range = NSRange(location: range.location, length: 2)
        }
        let rangeEnd = range.upperBound
        if range.length > 0, rangeEnd < string.length,
           string.character(at: rangeEnd) == 10,
           string.character(at: rangeEnd - 1) == 13
        {
            range = NSRange(location: range.location, length: range.length - 1)
        }
        return range
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        if updateLock > 0 { return false }
        lastSpaceIndex = nil
        let isUndoing = undoManager?.isUndoing ?? false
        guard !isUndoing, undoManager?.isRedoing != true else {
            let uiBundle = Bundle(for: UITextView.self)
            func localized(_ key: String) -> String {
                uiBundle.localizedString(forKey: key, value: nil, table: nil)
            }
            let pasteActions = ["Paste", localized("Paste")]
            if pasteActions.contains(undoManager?.undoActionName ?? "") {
                // This is handled by TextView so we need to block the default
                return false
            }
            let dictationActions = ["Dictation", localized("Dictation")]
            if isUndoing, range.length == 0,
               dictationActions.contains(undoManager?.undoActionName ?? "")
            {
                // Block weird behavior where undoing Dictation immediately
                // tries to re-insert the text
                return false
            }
            let replaceActions = ["Replace", localized("Replace")]
            if isUndoing, range == lastInsertedTextAndRange?.range,
               replaceActions.contains(undoManager?.undoActionName ?? ""),
               text == lastInsertedTextAndRange?.text
            {
                // Block weird behavior where undoing Writing tools immediately
                // tries to re-insert the text
                lastInsertedTextAndRange = nil
                return false
            }
            return true
        }
        let newRange = fixRange(range)
        var actionName: String?
        currentAction = currentAction ?? .typing
        if currentAction == .cut {
            actionName = "Cut"
            UIPasteboard.general.string = textView.textStorage
                .mutableString.substring(with: newRange)
        } else if currentAction == .paste || currentAction == .drop {
            actionName = "Paste"
        } else if text.isEmpty {
            currentAction = .delete
            actionName = "Delete"
        } else if newRange.length > 0 {
            actionName = "Replace"
        } else if newRange != range || text.contains(where: \.isNewline) || textView.textStorage.mutableString
            .substring(with: newRange).contains(where: \.isNewline)
        {
            // Need special handling if either:
            // * replaced a selection
            // * had to adjust range
            // * replacement text contains newlines
            // * replaced text contained newlines
            actionName = "Typing"
        }
        var text = text
        switch text {
        case "\n" where indentNewLines:
            text = "\n" + self.text.indentForLine(at: newRange.location)
            actionName = actionName ?? "Typing"
        case " " where disableDoubleSpacePeriodShortcut:
            if range.location > 0,
               textView.textStorage.mutableString
               .character(at: range.location - 1) == " ".utf16.first
            {
                lastSpaceIndex = range.location - 1
            }
        default:
            break
        }
        if let newText = textViewDelegate?.textView?(
            self,
            replacementForText: text
        ), newText != text {
            text = newText
            // Prevent double-application of text replacement
            actionName = actionName ?? "Typing"
        }
        guard uiTextViewDelegate?.textView?(
            textView,
            shouldChangeTextIn: newRange,
            replacementText: text
        ) ?? true else {
            // TODO: fix bugs when undoing paste when returning false
            return false
        }
        guard let actionName else {
            assert(range == newRange)
            lastInsertedTextAndRange = (text, range)
            return true
        }
        replace(newRange, with: text, for: NSLocalizedString(actionName, comment: ""))
        return false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScroll?(scrollView)
        updateLineNumbers()
    }

    private func isDelegateMethod(_ selector: Selector) -> Bool {
        protocol_getMethodDescription(
            TextViewDelegate.self,
            selector,
            false,
            true
        ).name != nil
    }

    override func responds(to selector: Selector) -> Bool {
        super.responds(to: selector) ||
            isDelegateMethod(selector) &&
            (delegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for _: Selector) -> Any? {
        delegate
    }
}

extension TextView: UITextDragDelegate, UITextDropDelegate {
    private func setText(_ text: String?) {
        textView.undoManager?.beginUndoGrouping()
        let oldText = textView.text ?? ""
        textView.undoManager?.registerUndo(withTarget: self) {
            $0.setText(oldText)
        }
        let actionName = NSLocalizedString("Drag", comment: "")
        textView.undoManager?.setActionName(actionName)
        if let text {
            textView.text = text
        }
        textView.undoManager?.endUndoGrouping()
    }

    func textDroppableView(
        _: UIView & UITextDroppable,
        willPerformDrop drop: UITextDropRequest
    ) {
        if drop.isSameView {
            currentAction = .drag
            setText(nil)
        } else {
            currentAction = .drop
        }
    }

    func textDroppableView(
        _: UIView & UITextDroppable,
        dropSessionDidEnd _: UIDropSession
    ) {
        textViewDidChange(textView)
    }
}

extension TextView: NSLayoutManagerDelegate {
    func layoutManager(
        _: NSLayoutManager,
        didCompleteLayoutFor _: NSTextContainer?,
        atEnd _: Bool
    ) {
        layoutManager.invalidateIndexRects()
    }

    func updateLineNumbers() {
        guard showLineNumbers else { return }
        gutterView.gutterWidth = layoutManager.gutterWidth
        gutterView.scrollOffset = textView.contentOffset.y
        gutterView.font = UIFontMetrics.default.scaledFont(for: font)
        gutterView.indexRects = Dictionary(
            uniqueKeysWithValues: layoutManager.indexRects.filter {
                $0.key <= lineCount
            }
        )
        // Calculate final line rect, which may be missing or wrong
        if text.isEmpty {
            if let textContainer = layoutManager.textContainers.first {
                var rect = layoutManager.usedRect(for: textContainer)
                rect.origin.y = textView.textContainerInset.top
                gutterView.indexRects[1] = rect
            }
        }
        gutterView.setNeedsLayout()
    }
}

private extension TextView {
    func avoidKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let rect = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        {
            _contentInset.bottom = rect.size.height - safeAreaInsets.bottom
            setNeedsLayout()
        }
    }

    @objc func keyboardWillHide(_: Notification) {
        _contentInset.bottom = .zero
        setNeedsLayout()
    }
}

private class LayoutManager: NSLayoutManager {
    private var lastParaLocation: Int = 0
    private var lastParaNumber: Int = 0

    var font: UIFont?
    var gutterWidth: CGFloat = 0
    private(set) var indexRects: [Int: CGRect] = [:]
    private var indexRectsNeedUpdate: Bool = false
    var drawInvisibleChars = false

    var textView: TextView? {
        delegate as! TextView?
    }

    func invalidateIndexRects() {
        indexRectsNeedUpdate = true
    }

    override func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorage.EditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(
            for: textStorage,
            edited: editMask,
            range: newCharRange,
            changeInLength: delta,
            invalidatedRange: invalidatedCharRange
        )

        if invalidatedCharRange.location < lastParaLocation {
            lastParaLocation = 0
            lastParaNumber = 0
            indexRectsNeedUpdate = true
        }
    }

    override func drawBackground(
        forGlyphRange glyphsToShow: NSRange,
        at origin: CGPoint
    ) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        var gutterRect: CGRect = .zero
        var paraNumber = 0
        var paraRange: NSRange?
        var paraHeight: CGFloat = 0
        let text = textStorage?.mutableString ?? ""
        let atts: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.tertiaryLabel,
        ]

        if indexRectsNeedUpdate {
            indexRects.removeAll()
            indexRectsNeedUpdate = false
        }

        enumerateLineFragments(
            forGlyphRange: glyphsToShow
        ) { rect, _, textContainer, glyphRange, _ in
            let charRange = self.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )

            // Calculate line number offsets
            if let paraRange, paraRange.contains(charRange.location) {
                // Already calculated for this paragraph
            } else {
                paraRange = text.paragraphRange(for: charRange)
                if var paraRange, charRange.location == paraRange.location {
                    paraNumber = self.paraNumber(for: charRange, in: text)
                    while paraRange.length > 0, text.substring(with: NSRange(
                        location: paraRange.upperBound - 1,
                        length: 1
                    )).first?.isNewline ?? false {
                        // Exclude trailing newline characters from paragraph
                        paraRange.length -= 1
                    }
                    paraHeight = self.boundingRect(
                        forGlyphRange: paraRange,
                        in: textContainer
                    ).height
                    gutterRect = CGRect(
                        x: origin.x,
                        y: rect.origin.y + origin.y,
                        width: self.gutterWidth,
                        height: rect.size.height
                    )
                    self.indexRects[paraNumber + 1] = gutterRect
                }
            }

            // Draw invisible characters
            if self.drawInvisibleChars {
                var lastRange: NSRange?
                text.enumerateSubstrings(
                    in: charRange,
                    options: .byComposedCharacterSequences
                ) { string, range, _, _ in
                    let symbol: String
                    let isNewline = string?.first?.isNewline ?? false
                    switch string {
                    case "\t":
                        symbol = "\u{21E5}"
                    case " ":
                        symbol = "\u{00B7}" // "\u{2423}"
                    case _ where isNewline:
                        symbol = "\u{00B6}"
                    case let string:
                        guard let char = string?.unicodeScalars.first,
                              CharacterSet.controlCharacters.contains(char) ||
                              CharacterSet.whitespaces.contains(char)
                        else {
                            lastRange = range
                            return
                        }
                        symbol = "█" // "\u{00B7}"
                    }
                    var characterRect = self.boundingRect(
                        forGlyphRange: range,
                        in: textContainer
                    )
                    // Workaround for CRLF being split in two
                    if characterRect.width == 0 {
                        if string == "\r" {
                            return
                        } else if string == "\n", range.location > 0 {
                            characterRect = self.boundingRect(
                                forGlyphRange: NSRange(
                                    location: range.location - 1,
                                    length: range.length + 1
                                ),
                                in: textContainer
                            )
                        }
                    }
                    // Workaround for spurious newline position on last line
                    if isNewline, characterRect.origin.x == 0 {
                        if let lastRange {
                            characterRect.origin.x += self.boundingRect(
                                forGlyphRange: lastRange,
                                in: textContainer
                            ).maxX
                        } else {
                            characterRect.origin.x += 5 // Magic!
                        }
                    }
                    lastRange = range
                    symbol.draw(
                        in: characterRect.offsetBy(dx: origin.x, dy: origin.y),
                        withAttributes: atts
                    )
                }
            }
        }

        // Add a final paragraph in case last line is blank
        indexRects[paraNumber + 2] = gutterRect.offsetBy(
            dx: 0,
            dy: paraHeight
        )

        textView?.updateLineNumbers()
    }

    private func paraNumber(for charRange: NSRange, in text: NSString) -> Int {
        if charRange.location == lastParaLocation {
            return lastParaNumber
        }

        var paraNumber = lastParaNumber
        if charRange.location < lastParaLocation {
            text.enumerateSubstrings(
                in: NSRange(
                    location: charRange.location,
                    length: lastParaLocation - charRange.location
                ),
                options: [.byParagraphs, .substringNotRequired, .reverse]
            ) { _, _, enclosingRange, stop in
                if enclosingRange.location <= charRange.location {
                    stop.pointee = true
                }
                paraNumber -= 1
            }

            lastParaLocation = charRange.location
            lastParaNumber = paraNumber
            return paraNumber
        }

        text.enumerateSubstrings(
            in: NSRange(
                location: lastParaLocation,
                length: charRange.location - lastParaLocation
            ),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, _, enclosingRange, stop in
            if enclosingRange.location >= charRange.location {
                stop.pointee = true
            }
            paraNumber += 1
        }

        lastParaLocation = charRange.location
        lastParaNumber = paraNumber
        return paraNumber
    }
}

private class LineNumberView: UIView {
    private var numberViews: [UILabel] = []

    var gutterWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var indexRects: [Int: CGRect] = [:]
    var font: UIFont = .preferredFont(forTextStyle: .body)

    override func layoutSubviews() {
        let atts: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel,
        ]

        var numberViews = numberViews
        for (i, rect) in indexRects {
            let rect = rect.offsetBy(dx: 0, dy: -scrollOffset)
            if rect.maxY < 0 || rect.minY > bounds.height {
                continue
            }
            let text = String(i)
            let size = text.size(withAttributes: atts)

            let view = numberViews.popLast() ?? {
                let view = UILabel()
                self.numberViews.append(view)
                addSubview(view)
                return view
            }()

            UIView.performWithoutAnimation {
                view.attributedText = NSAttributedString(
                    string: text,
                    attributes: atts
                )
                view.frame = rect.offsetBy(
                    dx: bounds.width - size.width - 4,
                    dy: 0
                )
            }
        }
        while let view = numberViews.popLast() {
            view.removeFromSuperview()
            self.numberViews.removeFirst()
        }
    }
}
