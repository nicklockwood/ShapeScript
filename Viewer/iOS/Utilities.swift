//
//  Utilities.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/06/2026.
//

import ShapeScript
import UIKit

// MARK: Types

typealias OSColor = UIColor
typealias OSFont = UIFont
typealias OSButton = UIButton
typealias OSTextView = UITextView

// MARK: General

let onlineHelpURL = URL(string: "https://shapescript.info/\(ShapeScript.version)/ios/")!

@MainActor func loadRTF(_ file: String) throws -> NSAttributedString {
    let file = Bundle.main.url(forResource: file, withExtension: "rtf")!
    let data = try! Data(contentsOf: file)
    let string = try NSMutableAttributedString(data: data, documentAttributes: nil)
    let range = NSRange(location: 0, length: string.length)
    string.addAttributes([.foregroundColor: UIColor.label], range: range)
    return string
}

// MARK: VoiceOver

@MainActor func voiceOver(_: String) {
    // Not implemented
}
