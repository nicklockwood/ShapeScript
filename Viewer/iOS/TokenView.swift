//
//  TokenView.swift
//  Subtext
//
//  Created by Nick Lockwood on 23/08/2022.
//

import UIKit

protocol TokenViewDelegate: TextViewDelegate {
    func tokens(for input: String) -> [TokenView.Token]
    func attributes(
        for tokenType: TokenView.TokenType
    ) -> [NSAttributedString.Key: Any]
}

class TokenView: TextView {
    struct TokenType: RawRepresentable, Hashable {
        var rawValue: String
    }

    struct Token: Hashable {
        var type: TokenType
        var range: Range<String.Index>
    }

    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        tokenize()
    }

    override var text: String {
        didSet { tokenize() }
    }

    override var font: UIFont {
        didSet { updateAttributes() }
    }

    override var textColor: UIColor {
        didSet { updateAttributes() }
    }

    private struct NSRangeToken {
        var type: TokenType
        var nsRange: NSRange
    }

    private var tokens: [NSRangeToken] = []

    private func tokenize() {
        guard let tokenViewDelegate = delegate as? TokenViewDelegate else {
            tokens = []
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        tokens = tokenViewDelegate.tokens(for: text).map {
            NSRangeToken(type: $0.type, nsRange: NSRange($0.range, in: text))
        }
        let tokenized = CFAbsoluteTimeGetCurrent()
        print("tokenized", tokenized - start)
        updateAttributes()
        let attributed = CFAbsoluteTimeGetCurrent()
        print("attributed", attributed - tokenized)
    }

    private func updateAttributes() {
        guard let tokenViewDelegate = delegate as? TokenViewDelegate else {
            return
        }

        let textStorage = textView.textStorage
        textStorage.beginEditing()

        let wholeRange = NSRange(location: 0, length: textStorage.length)
        var baseAttributes = [NSAttributedString.Key: Any]()
        baseAttributes[.font] = textView.font
        baseAttributes[.foregroundColor] = textColor
        textStorage.setAttributes(baseAttributes, range: wholeRange)

        var tokenAttributes = [TokenType: [NSAttributedString.Key: Any]]()
        for token in tokens {
            let attributes = tokenAttributes[token.type] ?? {
                let attributes = tokenViewDelegate.attributes(for: token.type)
                tokenAttributes[token.type] = attributes
                return attributes
            }()

            textStorage.addAttributes(attributes, range: token.nsRange)
        }

        textStorage.endEditing()
    }
}
