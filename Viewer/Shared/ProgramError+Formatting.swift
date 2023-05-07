//
//  ProgramError.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import ShapeScript

#if canImport(UIKit)
import UIKit
typealias OSColor = UIColor
typealias OSFont = UIFont
#else
import Cocoa
typealias OSColor = NSColor
typealias OSFont = NSFont
#endif

extension ProgramError {
    /// Returns a nicely-formatted rich text error message.
    func message(with source: String) -> NSAttributedString {
        let errorMessage = NSMutableAttributedString()
        let errorType = accessErrorURL == nil ? "Error" : "Permission Required"
        errorMessage.append(NSAttributedString(string: "\(errorType)\n\n", attributes: [
            .foregroundColor: OSColor.white,
            .font: OSFont.systemFont(ofSize: 17, weight: .bold),
        ]))
        let body = messageAndLocation(with: source)
        errorMessage.append(NSAttributedString(string: "\(body)\n\n", attributes: [
            .foregroundColor: OSColor.white.withAlphaComponent(0.7),
            .font: OSFont.systemFont(ofSize: 15, weight: .regular),
        ]))
        if let line = annotatedErrorLine(with: source),
           let font = OSFont(name: "Courier", size: 15)
        {
            errorMessage.append(NSAttributedString(
                string: "\(line)\n\n",
                attributes: [
                    .foregroundColor: OSColor.white,
                    .font: font,
                ]
            ))
        }
        if let hint = hint {
            errorMessage.append(NSAttributedString(string: "\(hint)\n\n", attributes: [
                .foregroundColor: OSColor.white.withAlphaComponent(0.7),
                .font: OSFont.systemFont(ofSize: 15, weight: .regular),
            ]))
        }
        return errorMessage
    }
}
