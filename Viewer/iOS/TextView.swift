//
//  TextView.swift
//  Subtext
//
//  Created by Nick Lockwood on 22/01/2022.
//

import UIKit

@objc protocol TextViewDelegate: UITextViewDelegate {
    @MainActor
    @objc optional func textView(_ textView: TextView, replacementForText text: String) -> String
}

// swiftformat:disable:next preferFinalClasses
class TextView: UIScrollView {
    private let layoutManager: LayoutManager = .init()
    private let gutterView = LineNumberView()
    private(set) var lineCount: Int = 0
    private var lastSpaceIndex: Int?
    private var previousSize: CGSize = .zero
    private var previousSelectedRange: NSRange?
    private var lastInsertedTextAndRange: (text: String, range: NSRange)?
    fileprivate var currentAction: TextAction?
    let textView: UITextView

    private var _contentInset: UIEdgeInsets = .zero {
        didSet { setNeedsLayout() }
    }

    // MARK: Lifecycle

    override init(frame: CGRect) {
        self.textView = TextView.textView(with: layoutManager)
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.textView = TextView.textView(with: layoutManager)
        super.init(coder: coder)
        setUp()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Configuration

    /// Get or set the text
    /// > Note: Setting the text this way bypasses `shouldChangeIn`and`textViewDidChange`
    /// > Note: Setting this property clears the undo buffer
    var text: String {
        get { textView.text }
        set {
            currentAction = nil
            guard newValue != textView.text else { return }
            textView.text = newValue
            updateLineCount()
            previousSize = .zero
            setNeedsLayout()
        }
    }

    /// The font to use for typed text
    /// > Note: size will be automatically adjusted based on accessibility text size preferences
    var font: UIFont = .monospacedSystemFont(ofSize: 15, weight: .regular) {
        didSet { updateAttributes() }
    }

    /// Display line numbers to the left of the text
    var showLineNumbers: Bool = false {
        didSet {
            guard showLineNumbers != oldValue else { return }
            updateLineCount()
            setNeedsLayout()
        }
    }

    /// Wrap lines automatically to fit the view width
    var wrapLines: Bool = false {
        didSet { setNeedsLayout() }
    }

    /// Indent new lines automatically to match the previous line
    var indentNewLines: Bool = true

    /// Mark invisible characters such as space, tab and linebreak
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

    /// Tab width (specified in multiples of the base font width)
    var tabWidth: Int = 4 {
        didSet { updateAttributes() }
    }
}

// MARK: Public API

extension TextView {
    override var contentInset: UIEdgeInsets {
        get { _contentInset }
        set { _contentInset = newValue }
    }

    override var undoManager: UndoManager? {
        textView.undoManager
    }

    @available(iOS 16.0, *)
    var findInteraction: UIFindInteraction? {
        textView.findInteraction
    }

    var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    var textColor: UIColor {
        get { textView.textColor ?? .label }
        set { updateTextColor() }
    }

    /// The base text attributes
    var typingAttributes: [NSAttributedString.Key: Any] {
        textView.typingAttributes
    }

    var selectedRange: NSRange {
        get { textView.selectedRange }
        set { textView.selectedRange = newValue }
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

    private func setUp() {
        layoutManager.delegate = self
        contentInsetAdjustmentBehavior = .never
        super.contentInset = .zero
        isDirectionalLockEnabled = true
        showsHorizontalScrollIndicator = true
        textView.adjustsFontForContentSizeCategory = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = false
        #if !os(visionOS)
        textView.keyboardDismissMode = .interactive
        #endif
        textView.allowsEditingTextAttributes = false
        textView.spellCheckingType = spellCheckingType
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        // This seems to have no effect when enabled, and since we
        // can't test it, the only safe option is to disable it
        textView.smartInsertDeleteType = .no
        if #available(iOS 17.0, *) {
            // Only meaningful when used in conjunction with UITextContentType
            textView.inlinePredictionType = .no
        }
        if #available(iOS 18.0, visionOS 2.0, *) {
            textView.mathExpressionCompletionType = .default
        }
        if #available(iOS 18.0, visionOS 2.4, *) {
            textView.writingToolsBehavior = .complete
            textView.allowedWritingToolsResultOptions = .plainText
        }
        updateAutocorrectOptions()
        textView.frame = bounds
        textView.delegate = self
        textView.textDragDelegate = self
        textView.textDropDelegate = self
        updateTextColor()
        updateAttributes()
        addSubview(textView)
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
                let maxY = max(
                    -textView.contentInset.top,
                    textView.contentSize.height
                        - textView.frame.height + textView.contentInset.bottom
                )
                if textView.contentOffset.y > maxY {
                    textView.contentOffset.y = maxY
                }
            }
        }
        // Workaround for resizing in background leaving layout in a broken state
        if UIApplication.shared.applicationState == .background {
            previousSize = .zero
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
        updateAttributes()
    }

    @objc func updateAttributes() {
        // Update font
        textView.font = UIFontMetrics.default.scaledFont(for: font)
        textView.typingAttributes[.font] = textView.font
        // Update tab indent
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.defaultTabInterval = NSString(" ")
            .size(withAttributes: typingAttributes)
            .width * CGFloat(tabWidth)
        paragraphStyle.tabStops = []
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        // Apply new attributes
        let range = NSRange(location: 0, length: textView.textStorage.length)
        textView.textStorage.addAttributes(typingAttributes, range: range)
        gutterView.attributes = typingAttributes
        setNeedsLayout()
    }

    /// Perform updates to the textView without triggering delegate or special behaviors
    func performWithoutUpdates(_ block: () -> Void) {
        textView.delegate = nil
        block()
        textView.delegate = self
        currentAction = nil
    }
}

// MARK: UIKeyInput

extension TextView: UIKeyInput {
    var hasText: Bool {
        textView.hasText
    }

    func insertText(_ text: String) {
        textView.insertText(text)
    }

    func deleteBackward() {
        textView.deleteBackward()
    }
}

// MARK: UITextInput

extension TextView {
    func text(in range: UITextRange) -> String? {
        textView.text(in: range)
    }

    func replace(_ range: UITextRange, withText text: String) {
        textView.replace(range, withText: text)
    }

    var selectedTextRange: UITextRange? {
        // Note: proxied value is actually read/write
        textView.selectedTextRange
    }

    func textRange(
        from fromPosition: UITextPosition,
        to toPosition: UITextPosition
    ) -> UITextRange? {
        textView.textRange(from: fromPosition, to: toPosition)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        textView.position(from: position, offset: offset)
    }

    func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        textView.position(from: position, in: direction, offset: offset)
    }

    func shouldChangeText(in range: UITextRange, replacementText text: String) -> Bool {
        textView.shouldChangeText(in: range, replacementText: text)
    }
}

// MARK: UIResponderStandardEditActions

extension TextView {
    override func cut(_ sender: Any?) {
        textView.cut(sender)
    }

    override func copy(_ sender: Any?) {
        textView.copy(sender)
    }

    override func paste(_ sender: Any?) {
        textView.paste(sender)
    }

    override func selectAll(_ sender: Any?) {
        textView.selectAll(sender)
    }
}

// MARK: UITextViewDelegate

extension TextView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if let undoManager, undoManager.isUndoing || undoManager.isRedoing {
            updateLineCount()
        } else {
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
                if let newText = replacementFor(text) {
                    // Replacing text this way clears the undo buffer, so ideally
                    // we don't ever want this to happen - it's only for cases where
                    // we aren't able to intercept the update at an earlier stage
                    DispatchQueue.main.async { self.text = newText }
                    return
                } else {
                    updateLineCount()
                }
            }
            // Clean up object replacement characters left after dictation
            // TODO: these are set and then immediately removed anyway, so maybe we can
            // just detect that it happened and not forward the textViewDidChange event?
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
        // Fix invalid selection range
        let newRange = fixRange(textView.selectedRange)
        if newRange != textView.selectedRange {
            textView.selectedRange = newRange
            return
        }

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

        // Track range
        previousSelectedRange = textView.selectedRange
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        lastSpaceIndex = nil
        let isUndoing = undoManager?.isUndoing ?? false
        guard !isUndoing, undoManager?.isRedoing != true else {
            if undoManager?.undoActionName == localized("Paste") {
                // This is handled by TextView so we need to block the default
                return false
            }
            if isUndoing, range.length == 0,
               undoManager?.undoActionName == localized("Dictation")
            {
                // Block weird behavior where undoing Dictation immediately
                // tries to re-insert the text
                return false
            }
            if isUndoing, range == lastInsertedTextAndRange?.range,
               undoManager?.undoActionName == localized("Replace"),
               text == lastInsertedTextAndRange?.text
            {
                // Block weird behavior where undoing Writing tools immediately
                // tries to re-insert the text
                lastInsertedTextAndRange = nil
                return false
            }
            return true
        }
        let fixedRange = fixRange(range)
        var text = text
        let mutableString = textView.textStorage.mutableString
        switch currentAction {
        case .replace, .delete, .typing, .drag:
            assertionFailure("Should never happen")
            currentAction = nil
            return true
        case .cut:
            // Ensure copy is called even though cut event is blocked
            copy(nil)
        case .paste:
            break
        case nil where text == "\n":
            currentAction = .typing
            text += self.text.indentForLine(at: fixedRange.location)
        case nil where text.isEmpty:
            switch fixedRange.length {
            case 0:
                // Delete with an empty range is triggered after autocorrect insertions
                // when there was text selected beforehand. Best to just ignore it
                return true
            case 1 where !"\n\r".contains(mutableString.substring(with: fixedRange)):
                // Probably a backspace keypress
                // Ideally we'd like to intercept this but that breaks Chinese input
                return true
            default:
                currentAction = .delete
            }
        case nil where fixedRange.length > 0:
            // This is a replace action, possibly triggered by autocorrection
            // We can block it, but we can't safely replace it at this point
            return uiTextViewDelegate?.textView?(
                textView,
                shouldChangeTextIn: fixedRange,
                replacementText: text
            ) ?? true
        case nil where [".", ",", ";", ":", "!", "?"].contains(text):
            if mutableString.character(at: fixedRange.location - 1) != text.utf16.first {
                currentAction = .typing
            }
        case nil where text == " ":
            if disableDoubleSpacePeriodShortcut, fixedRange.location > 0,
               mutableString.character(at: fixedRange.location - 1) == " ".utf16.first
            {
                lastSpaceIndex = fixedRange.location - 1
            }
        case nil:
            break
        }
        if let newText = replacementFor(text) {
            text = newText
            // Prevent double-application of text replacement
            currentAction = currentAction ?? .typing
        }
        guard uiTextViewDelegate?.textView?(
            textView,
            shouldChangeTextIn: fixedRange,
            replacementText: text
        ) ?? true else {
            return false
        }
        guard let currentAction else {
            assert(range == fixedRange)
            lastInsertedTextAndRange = (text, range)
            return true
        }
        replace(fixedRange, with: text, for: currentAction.actionName)
        return false
    }

    // MARK: Automatic forwarding of UITextViewDelegate methods

    private func isMethod(_ selector: Selector, of proto: Protocol) -> Bool {
        protocol_getMethodDescription(
            proto,
            selector,
            false,
            true
        ).name != nil
    }

    override func responds(to selector: Selector) -> Bool {
        super.responds(to: selector) || (
            isMethod(selector, of: UITextViewDelegate.self) &&
                delegate?.responds(to: selector) ?? false
        )
    }

    override func forwardingTarget(for selector: Selector) -> Any? {
        if isMethod(selector, of: UITextViewDelegate.self) {
            return delegate
        }
        return nil
    }
}

// MARK: UIScrollViewDelegate

extension TextView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScroll?(scrollView)
        updateLineNumbers()
    }
}

// MARK: Drag & Drop support

extension TextView: UITextDragDelegate, UITextDropDelegate {
    private func setText(_ text: String?) {
        textView.undoManager?.beginUndoGrouping()
        let oldText = textView.text ?? ""
        textView.undoManager?.registerUndo(withTarget: self) {
            $0.setText(oldText)
        }
        let actionName = localized("Drag")
        textView.undoManager?.setActionName(actionName)
        if let text {
            textView.text = text
        }
        textView.undoManager?.endUndoGrouping()
    }

    func textDroppableView(_: UIView & UITextDroppable, willPerformDrop drop: UITextDropRequest) {
        if drop.isSameView {
            currentAction = .drag
            setText(nil)
        } else {
            currentAction = .paste
        }
    }

    func textDroppableView(_: UIView & UITextDroppable, dropSessionDidEnd _: UIDropSession) {
        textViewDidChange(textView)
    }
}

// MARK: LayoutManager

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

private final class LayoutManager: NSLayoutManager {
    private var lastParaLocation: Int = 0
    private var lastParaNumber: Int = 0

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

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage, let textView else { return }

        var gutterRect: CGRect = .zero
        var paraNumber = 0
        var paraRange: NSRange?
        var paraHeight: CGFloat = 0
        let text = textStorage.mutableString

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
                    var attributes = textView.typingAttributes
                    attributes[.foregroundColor] = UIColor.tertiaryLabel

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
                        withAttributes: attributes
                    )
                }
            }
        }

        // Add a final paragraph in case last line is blank
        indexRects[paraNumber + 2] = gutterRect.offsetBy(
            dx: 0,
            dy: paraHeight
        )

        textView.updateLineNumbers()
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

// MARK: Private API

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

    var textViewDelegate: TextViewDelegate? {
        delegate as? TextViewDelegate
    }

    var uiTextViewDelegate: UITextViewDelegate? {
        delegate as? UITextViewDelegate
    }

    func updateAutocorrectOptions() {
        // This is tricky as it triggers updates that appear like typing, but
        // which cannot be intercepted without screwing up the text layout
        textView.autocorrectionType = disableAutocorrection ? .no : .default
        // This is safe as it doesn't affect text length
        textView.autocapitalizationType = disableAutocorrection ? .none : .sentences
    }

    func replacementFor(_ text: String) -> String? {
        if let replacement = textViewDelegate?.textView?(self, replacementForText: text),
           replacement != text
        {
            return replacement
        }
        return nil
    }

    /// Perform an undoable replacement of the text for a given action name
    func replace(_ range: NSRange, with text: String, for action: String) {
        let fullOldText = textView.text ?? ""
        let oldText = textView.textStorage.mutableString.substring(with: range)
        let newRange = NSRange(location: range.location, length: text.utf16.count)
        textView.undoManager?.beginUndoGrouping()
        textView.undoManager?.registerUndo(withTarget: self) {
            let fullRange = NSRange(location: 0, length: $0.textView.textStorage.length)
            if newRange.upperBound <= fullRange.upperBound,
               $0.textView.textStorage.mutableString.substring(with: newRange) == text
            {
                $0.replace(newRange, with: oldText, for: action)
                if $0.undoManager?.isUndoing ?? false, !"\n\r\n\r".contains(oldText) {
                    // When undoing restore the original range
                    $0.textView.selectedRange = range
                }
            } else {
                // Something went wrong, so we'll just restore the full text
                $0.replace(fullRange, with: fullOldText, for: action)
            }
        }
        textView.undoManager?.setActionName(action)
        textView.textStorage.mutableString.replaceCharacters(in: range, with: text)
        // Prevent font being reset when pasting into an empty document
        textView.textStorage.setAttributes(typingAttributes, range: newRange)
        textView.selectedRange = NSRange(location: newRange.upperBound, length: 0)
        updateLineCount(oldText: oldText, newText: text)
        textViewDidChange(textView)
        textView.undoManager?.endUndoGrouping()
        // Workaround for double insertion bug
        lastInsertedTextAndRange = (text, range)
    }

    func fixRange(_ range: NSRange) -> NSRange {
        // Avoid splitting Windows (CRLF) linebreaks
        var range = range
        let string = textView.textStorage.mutableString
        if range.location > 0, range.location < string.length,
           string.character(at: range.location) == 10,
           string.character(at: range.location - 1) == 13
        {
            if let prev = previousSelectedRange, prev.location > range.location {
                range = NSRange(location: range.location - 1, length: range.length + 1)
            } else {
                range = NSRange(location: range.location + 1, length: range.length - 1)
            }
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
            if let prev = previousSelectedRange, prev.upperBound > rangeEnd {
                range = NSRange(location: range.location, length: range.length - 1)
            } else {
                range = NSRange(location: range.location, length: range.length + 1)
            }
        }
        return range
    }

    func updateTextColor() {
        textView.textColor = textColor
        textView.typingAttributes[.foregroundColor] = textColor
    }

    func updateInsets() {
        var inset = UIEdgeInsets(
            top: _contentInset.top + safeAreaInsets.top,
            left: _contentInset.left + safeAreaInsets.left,
            bottom: _contentInset.bottom + safeAreaInsets.bottom,
            right: _contentInset.right + safeAreaInsets.right
        )
        layoutManager.drawInvisibleChars = showInvisibleCharacters
        if showLineNumbers {
            layoutManager.gutterWidth = ceil(
                String(lineCount).size(withAttributes: typingAttributes).width + 8
            )
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

    func updateLineCount(oldText: String, newText: String) {
        guard showLineNumbers else {
            return
        }
        let count = newText.lineCount - oldText.lineCount
        if count != 0 {
            lineCount += count
            setNeedsLayout()
        }
    }

    // MARK: keyboard avoidance

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
        }
    }

    @objc func keyboardWillHide(_: Notification) {
        _contentInset.bottom = .zero
    }
}

// MARK: UITextView subclass

/// Get existing localized text for a given label
private func localized(_ key: String) -> String {
    Bundle(for: UITextView.self).localizedString(forKey: key, value: nil, table: nil)
}

private enum TextAction: String {
    case typing, delete, cut, paste, drag, replace

    var actionName: String {
        localized(rawValue.capitalized)
    }
}

private final class _UITextView: UITextView {
    private var textView: TextView? {
        delegate as! TextView?
    }

    // MARK: UIResponder

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

    override func captureTextFromCamera(_: Any?) {
        // Disabled, as it doesn't work correctly
        // TODO: might be OK now on iOS 18+; should verify this
    }

    // MARK: UIResponderStandardEditActions

    override func cut(_ sender: Any?) {
        if selectedTextRange != nil {
            textView?.currentAction = .cut
            super.cut(sender)
        }
    }

    override func paste(_ sender: Any?) {
        if UIPasteboard.general.string != nil {
            textView?.currentAction = .paste
            super.paste(sender)
        }
    }

    // MARK: UIKeyInput

    /// This is called when delete key is pressed and when undoing typing
    /// It doesn't trigger shouldChangeText but does call textViewDidChange
    override func deleteBackward() {
        super.deleteBackward()
    }

    /// This is called whenever typing
    /// It doesn't trigger shouldChangeText but does call textViewDidChange
    override func insertText(_ text: String) {
        super.insertText(text)
    }

    // MARK: UITextInput

    /// This invokes the `shouldChangeTextIn(_:replacementText:) delegate method
    /// It's not called by any of the standard typing functions
    override func shouldChangeText(in range: UITextRange, replacementText text: String) -> Bool {
        // NOTE: there is no super-implementation
        let range = self.range(for: range)
        return delegate?.textView?(self, shouldChangeTextIn: range, replacementText: text) ?? true
    }

    /// This is called directly by the Translate function, already inside an undo block
    /// It doesn't trigger shouldChangeText but does call textViewDidChange
    override func replace(_ range: UITextRange, withText text: String) {
        textView?.currentAction = .replace
        let text = textView?.replacementFor(text) ?? text
        let oldText = self.text(in: range) ?? ""
        super.replace(range, withText: text)
        textView?.updateLineCount(oldText: oldText, newText: text)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard let textView = superview as? TextView, !textView.wrapLines else {
            return rect
        }
        // workaround for wrong value when caret goes off the right
        // of the screen due to wrapping having been disabled
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

// MARK: LineNumberView

private final class LineNumberView: UIView {
    private var numberViews: [UILabel] = []

    var gutterWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var indexRects: [Int: CGRect] = [:]
    var attributes: [NSAttributedString.Key: Any] = [:]

    override func layoutSubviews() {
        var attributes = attributes
        attributes[.foregroundColor] = UIColor.secondaryLabel

        var numberViews = numberViews
        for (i, rect) in indexRects {
            let rect = rect.offsetBy(dx: 0, dy: -scrollOffset)
            if rect.maxY < 0 || rect.minY > bounds.height {
                continue
            }
            let text = String(i)
            let size = text.size(withAttributes: attributes)

            let view = numberViews.popLast() ?? {
                let view = UILabel()
                self.numberViews.append(view)
                addSubview(view)
                return view
            }()

            UIView.performWithoutAnimation {
                view.attributedText = NSAttributedString(
                    string: text,
                    attributes: attributes
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

// MARK: Utilities

extension UITextInput {
    /// Convert UITextRange to NSRange
    func range(for textRange: UITextRange) -> NSRange {
        let location = offset(from: beginningOfDocument, to: textRange.start)
        let length = offset(from: textRange.start, to: textRange.end)
        return NSRange(location: location, length: length)
    }

    /// Convert NSRange to UITextRange
    func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length)
        else {
            return nil
        }
        return textRange(from: start, to: end)
    }
}

private extension String {
    /// Count the number of lines in the string
    var lineCount: Int {
        reduce(1) { $0 + ("\r\n\n\r".contains($1) ? 1 : 0) }
    }

    /// Compute the index for the start of the line at the specified String index
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

    /// Compute the indent for the line at the specified UTF16 offset
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
