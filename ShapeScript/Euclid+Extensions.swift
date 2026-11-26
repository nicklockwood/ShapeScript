//
//  Euclid+Extensions.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

extension Color {
    var isFinite: Bool {
        components.allSatisfy(\.isFinite)
    }

    init(unchecked components: [Double]) {
        if let color = Color(components) {
            self = color
        } else {
            assertionFailure()
            self = .clear
        }
    }
}

extension Angle {
    var halfturns: Double {
        radians / .pi
    }

    init(halfturns: Double) {
        self.init(radians: halfturns * .pi)
    }

    static func halfturns(_ halfturns: Double) -> Angle {
        self.init(halfturns: halfturns)
    }
}

extension Vector {
    var isFinite: Bool {
        components.allSatisfy(\.isFinite)
    }
}

extension Bounds {
    var isFinite: Bool {
        self == .empty || min.components.allSatisfy(\.isFinite) &&
            max.components.allSatisfy(\.isFinite)
    }
}

extension Rotation {
    var rollYawPitchInHalfTurns: [Double] {
        [roll.halfturns, yaw.halfturns, pitch.halfturns]
    }

    var isFinite: Bool {
        rollYawPitchInHalfTurns.allSatisfy(\.isFinite)
    }

    init(rollYawPitchInHalfTurns: [Double]) {
        var roll = 0.0, yaw = 0.0, pitch = 0.0
        switch rollYawPitchInHalfTurns.count {
        case 3...:
            pitch = rollYawPitchInHalfTurns[2]
            fallthrough
        case 2:
            yaw = rollYawPitchInHalfTurns[1]
            fallthrough
        case 1:
            roll = rollYawPitchInHalfTurns[0]
        default:
            break
        }
        self.init(
            roll: .halfturns(roll),
            yaw: .halfturns(yaw),
            pitch: .halfturns(pitch)
        )
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(CoreText)
extension NSAttributedString {
    convenience init(
        string: String,
        font: String?,
        color: Color?,
        linespacing: Double?,
        letterspacing: Double? = nil
    ) {
        var fontName = (font ?? "Helvetica") as CFString
        #if canImport(CoreGraphics)
        fontName = CGFont(fontName)?.postScriptName ?? fontName
        #endif
        let font = CTFontCreateWithName(fontName as CFString, 1, nil)
        var attributes = [NSAttributedString.Key.font: font as Any]
        if let letterspacing, letterspacing != 0 {
            attributes[NSAttributedString.Key(kCTTrackingAttributeName as String)] = letterspacing
        }
        #if canImport(AppKit) || canImport(UIKit)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(linespacing ?? 0)
        attributes[.paragraphStyle] = paragraphStyle
        attributes[.foregroundColor] = color.map(OSColor.init)
        #endif
        self.init(string: string, attributes: attributes)
    }
}
#endif

extension Path {
    /// Create an array of text paths
    static func text(
        _ text: [TextValue],
        width: Double? = nil,
        detail: Int = 2,
        isCancelled: CancellationHandler
    ) -> [Path] {
        #if canImport(CoreText)
        let attributedString = NSMutableAttributedString()
        for text in text {
            var string = text.string
            if attributedString.length > 0 {
                string = "\n\(string)"
            }
            attributedString.append(NSAttributedString(
                string: string,
                font: text.font,
                color: text.color,
                linespacing: text.linespacing,
                letterspacing: text.letterspacing
            ))
        }
        return [Path].text(
            attributedString,
            width: width,
            detail: detail,
            isCancelled: isCancelled
        )
        #else
        // TODO: throw error when CoreText not available
        return []
        #endif
    }
}
