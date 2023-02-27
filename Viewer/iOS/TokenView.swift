//
//  TokenView.swift
//  Subtext
//
//  Created by Nick Lockwood on 23/08/2022.
//

import UIKit

protocol TokenViewDelegate: UITextViewDelegate {
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

    override var text: String {
        didSet {
            tokenize()
        }
    }

    override func textViewDidChange(_ textView: UITextView) {
        tokenize()
        super.textViewDidChange(textView)
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
        createAttributes(for: tokens)
        let attributed = CFAbsoluteTimeGetCurrent()
        print("attributed", attributed - tokenized)
    }

    private func createAttributes(for tokens: [NSRangeToken]) {
        guard let tokenViewDelegate = delegate as? TokenViewDelegate else {
            return
        }

        let textStorage = textView.textStorage
        textStorage.beginEditing()

        var attributes = [NSAttributedString.Key: Any]()
        attributes[.font] = textView.font
        attributes[.foregroundColor] = textView.textColor

        let wholeRange = NSRange(location: 0, length: text.utf16.count)
        textStorage.setAttributes(attributes, range: wholeRange)

        var tokenAttributes = [TokenType: [NSAttributedString.Key: Any]]()
        for token in tokens {
            let attributes = tokenAttributes[token.type] ?? {
                let attr = tokenViewDelegate.attributes(for: token.type)
                tokenAttributes[token.type] = attr
                return attr
            }()

            if !attributes.isEmpty {
                textStorage.addAttributes(attributes, range: token.nsRange)
            }
        }

        textStorage.endEditing()
    }
}
