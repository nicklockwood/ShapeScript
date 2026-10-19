//
//  ProgramError+Formatting.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import ShapeScript

#if canImport(UIKit)
import UIKit
#else
import Cocoa
#endif

extension ProgramError {
    /// Returns a nicely-formatted rich text error message.
    func message(with source: String) -> NSAttributedString {
        let errorMessage = NSMutableAttributedString()
        errorMessage.append(NSAttributedString(string: "\(title)\n\n", attributes: [
            .foregroundColor: OSColor.white,
            .font: OSFont.systemFont(ofSize: 17, weight: .bold),
        ]))
        let body = messageAndLocation(with: source)
        errorMessage.append(NSAttributedString(string: "\(body)\n\n", attributes: [
            .foregroundColor: OSColor.white.withAlphaComponent(0.7),
            .font: OSFont.systemFont(ofSize: 15, weight: .regular),
        ]))
        if let line = annotatedErrorLine(with: source),
           let (sourceLine, range) = errorLineAndRange(with: source),
           let font = OSFont(name: "Courier", size: 15)
        {
            errorMessage.append(NSAttributedString(
                string: "\(line)\n\n",
                attributes: [
                    .foregroundColor: OSColor.white,
                    .font: font,
                    .errorExcerpt: ErrorExcerpt(line: sourceLine, range: range),
                ]
            ))
        }
        if let hint {
            errorMessage.append(NSAttributedString(string: "\(hint)\n\n", attributes: [
                .foregroundColor: OSColor.white.withAlphaComponent(0.7),
                .font: OSFont.systemFont(ofSize: 15, weight: .regular),
            ]))
        }
        return errorMessage
    }
}

extension NSAttributedString {
    func wrappingErrorExcerpt(toWidth width: CGFloat) -> NSAttributedString {
        guard width.isFinite, width > 0 else { return self }
        let result = NSMutableAttributedString(attributedString: self)
        enumerateAttribute(
            .errorExcerpt,
            in: NSRange(location: 0, length: length),
            options: .reverse
        ) { value, range, _ in
            guard let excerpt = value as? ErrorExcerpt else { return }
            let attributes = self.attributes(at: range.location, effectiveRange: nil)
            result.replaceCharacters(in: range, with: excerpt.layout(width: width, attributes: attributes))
        }
        return result
    }
}

private extension NSAttributedString.Key {
    static let errorExcerpt = NSAttributedString.Key("ShapeScript.errorExcerpt")
}

final class ErrorExcerpt: NSObject {
    let line: String
    let range: NSRange

    init(line: String, range: Range<String.Index>) {
        self.range = NSRange(range, in: line)
        self.line = line
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ErrorExcerpt else { return false }
        return line == other.line && range == other.range
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(line)
        hasher.combine(range)
        return hasher.finalize()
    }

    func layout(width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = attributes
        attributes.removeValue(forKey: .errorExcerpt)
        let storage = NSTextStorage(string: line, attributes: attributes)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        attributes[.paragraphStyle] = paragraph
        let caretWidth = max(1, NSAttributedString(string: "^", attributes: attributes).size().width)
        let result = NSMutableAttributedString()
        manager.enumerateLineFragments(
            forGlyphRange: manager.glyphRange(for: container)
        ) { _, usedRect, _, glyphs, stop in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let fragment = (self.line as NSString).substring(with: characters)
            result.append(NSAttributedString(string: fragment + "\n", attributes: attributes))

            let overlap = NSIntersectionRange(self.range, characters)
            let insertion = self.range.length == 0 && self.range.location >= characters.location &&
                (self.range.location < NSMaxRange(characters) || NSMaxRange(characters) == storage.length)
            guard overlap.length > 0 || insertion else { return }

            let bounds: CGRect
            if insertion {
                let x: CGFloat
                if self.range.location < storage.length {
                    let glyph = manager.glyphIndexForCharacter(at: self.range.location)
                    x = manager.location(forGlyphAt: glyph).x
                } else {
                    x = usedRect.maxX
                }
                bounds = CGRect(x: x, y: 0, width: caretWidth, height: 0)
            } else {
                let highlighted = manager.glyphRange(forCharacterRange: overlap, actualCharacterRange: nil)
                bounds = manager.boundingRect(forGlyphRange: highlighted, in: container)
            }
            let indent = min(max(0, bounds.minX), max(0, width - caretWidth))
            let count = max(1, min(Int(ceil(bounds.width / caretWidth)), Int((width - indent) / caretWidth)))
            let caretParagraph = NSMutableParagraphStyle()
            caretParagraph.lineBreakMode = .byClipping
            caretParagraph.firstLineHeadIndent = indent
            caretParagraph.headIndent = indent
            var caretAttributes = attributes
            caretAttributes[.paragraphStyle] = caretParagraph
            result.append(NSAttributedString(
                string: String(repeating: "^", count: count) + "\n",
                attributes: caretAttributes
            ))
            if NSMaxRange(self.range) <= NSMaxRange(characters) {
                stop.pointee = true
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: attributes))
        return result
    }
}
