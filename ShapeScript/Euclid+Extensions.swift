//
//  Euclid+Extensions.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

public extension Color {
    init?(hexString: String) {
        var string = hexString
        if hexString.hasPrefix("#") {
            string = String(string.dropFirst())
        }
        switch string.count {
        case 3:
            string += "f"
            fallthrough
        case 4:
            let chars = Array(string)
            let red = chars[0]
            let green = chars[1]
            let blue = chars[2]
            let alpha = chars[3]
            string = "\(red)\(red)\(green)\(green)\(blue)\(blue)\(alpha)\(alpha)"
        case 6:
            string += "ff"
        case 8:
            break
        default:
            return nil
        }
        guard let rgba = Double("0x" + string).flatMap({
            UInt32(exactly: $0)
        }) else {
            return nil
        }
        let red = Double((rgba & 0xFF00_0000) >> 24) / 255
        let green = Double((rgba & 0x00FF_0000) >> 16) / 255
        let blue = Double((rgba & 0x0000_FF00) >> 8) / 255
        let alpha = Double((rgba & 0x0000_00FF) >> 0) / 255
        self.init(unchecked: [red, green, blue, alpha])
    }
}

extension Color {
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

extension Rotation {
    var rollYawPitchInHalfTurns: [Double] {
        [roll.radians / .pi, yaw.radians / .pi, pitch.radians / .pi]
    }

    init?(rollYawPitchInHalfTurns: [Double]) {
        var roll = 0.0, yaw = 0.0, pitch = 0.0
        switch rollYawPitchInHalfTurns.count {
        case 3:
            pitch = rollYawPitchInHalfTurns[2]
            fallthrough
        case 2:
            yaw = rollYawPitchInHalfTurns[1]
            fallthrough
        case 1:
            roll = rollYawPitchInHalfTurns[0]
        case 0:
            break
        default:
            return nil
        }
        self.init(
            roll: .radians(roll * .pi),
            yaw: .radians(yaw * .pi),
            pitch: .radians(pitch * .pi)
        )
    }

    init(unchecked rollYawPitchInHalfTurns: [Double]) {
        if let rotation = Rotation(rollYawPitchInHalfTurns: rollYawPitchInHalfTurns) {
            self = rotation
        } else {
            assertionFailure()
            self = .identity
        }
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(CoreText)
private extension NSAttributedString {
    convenience init(string: String, font: String?, color: Color?, linespacing: Double?) {
        var fontName = (font ?? "Helvetica") as CFString
        #if canImport(CoreGraphics)
        fontName = CGFont(fontName)?.postScriptName ?? fontName
        #endif
        let font = CTFontCreateWithName(fontName as CFString, 1, nil)
        var attributes = [NSAttributedString.Key.font: font as Any]
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
        detail: Int = 2
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
                linespacing: text.linespacing
            ))
        }
        return Path.text(attributedString, width: width, detail: detail)
        #else
        // TODO: throw error when CoreText not available
        return []
        #endif
    }
}
