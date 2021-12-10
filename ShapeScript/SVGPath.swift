//
//  SVGPath.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

#if canImport(CoreGraphics)

import CoreGraphics
import Foundation

extension CGPath {
    static func fromSVG(_ svgPath: String) throws -> CGPath {
        try fromSVG(SVGPath(svgPath))
    }

    static func fromSVG(_ svgPath: SVGPath) throws -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        for command in svgPath.commands {
            switch command {
            case let .moveTo(point):
                path.move(to: point)
            case let .lineTo(point):
                path.addLine(to: point)
            case let .quadratic(control, point):
                path.addQuadCurve(to: point, control: control)
            case let .cubic(control1, control2, point):
                path.addCurve(to: point, control1: control1, control2: control2)
            case let .arc(arc):
                path.addArc(arc)
            case .end:
                path.closeSubpath()
            }
        }
        return path
    }
}

private extension CGMutablePath {
    func addArc(_ arc: SVGArc) {
        let px = currentPoint.x, py = currentPoint.y
        var rx = abs(arc.radius.width), ry = abs(arc.radius.height)
        let xr = arc.rotation
        let largeArcFlag = arc.largeArc
        let sweepFlag = arc.sweep
        let cx = arc.end.x, cy = arc.end.y
        let sinphi = sin(xr), cosphi = cos(xr)

        func vectorAngle(
            _ ux: CGFloat, _ uy: CGFloat,
            _ vx: CGFloat, _ vy: CGFloat
        ) -> CGFloat {
            let sign: CGFloat = (ux * vy - uy * vx < 0) ? -1 : 1
            let umag = sqrt(ux * ux + uy * uy), vmag = sqrt(vx * vx + vy * vy)
            let dot = ux * vx + uy * vy
            return sign * acos(max(-1, min(1, dot / (umag * vmag))))
        }

        func toEllipse(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let x = x * rx, y = y * ry
            let xp = cosphi * x - sinphi * y, yp = sinphi * x + cosphi * y
            return CGPoint(x: xp + centerx, y: yp + centery)
        }

        let dx = (px - cx) / 2, dy = (py - cy) / 2
        let pxp = cosphi * dx + sinphi * dy, pyp = -sinphi * dx + cosphi * dy
        if pxp == 0, pyp == 0 {
            return
        }

        let lambda = pow(pxp, 2) / pow(rx, 2) + pow(pyp, 2) / pow(ry, 2)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let rxsq = pow(rx, 2), rysq = pow(ry, 2)
        let pxpsq = pow(pxp, 2), pypsq = pow(pyp, 2)

        var radicant = max(0, rxsq * rysq - rxsq * pypsq - rysq * pxpsq)
        radicant /= (rxsq * pypsq) + (rysq * pxpsq)
        radicant = sqrt(radicant) * (largeArcFlag != sweepFlag ? -1 : 1)

        let centerxp = radicant * rx / ry * pyp
        let centeryp = radicant * -ry / rx * pxp

        let centerx = cosphi * centerxp - sinphi * centeryp + (px + cx) / 2
        let centery = sinphi * centerxp + cosphi * centeryp + (py + cy) / 2

        let vx1 = (pxp - centerxp) / rx, vy1 = (pyp - centeryp) / ry
        let vx2 = (-pxp - centerxp) / rx, vy2 = (-pyp - centeryp) / ry

        var a1 = vectorAngle(1, 0, vx1, vy1)
        var a2 = vectorAngle(vx1, vy1, vx2, vy2)
        if sweepFlag, a2 > 0 {
            a2 -= .pi * 2
        } else if !sweepFlag, a2 < 0 {
            a2 += .pi * 2
        }

        let segments = max(ceil(abs(a2) / (.pi / 2)), 1)
        a2 /= segments
        let a = 4 / 3 * tan(a2 / 4)
        for _ in 0 ..< Int(segments) {
            let x1 = cos(a1), y1 = sin(a1)
            let x2 = cos(a1 + a2), y2 = sin(a1 + a2)

            let p1 = toEllipse(x1 - y1 * a, y1 + x1 * a)
            let p2 = toEllipse(x2 + y2 * a, y2 - x2 * a)
            let p = toEllipse(x2, y2)

            addCurve(to: p, control1: p1, control2: p2)
            a1 += a2
        }
    }
}

enum SVGErrorType: Error {
    case unexpectedToken(String)
    case unexpectedArgument(for: String, expected: Int)
    case missingArgument(for: String, expected: Int)
    case unsupportedEllipticalArc

    var message: String {
        switch self {
        case let .unexpectedToken(string):
            return "Unexpected token '\(string)'"
        case let .unexpectedArgument(command, _):
            return "Too many arguments for '\(command)'"
        case let .missingArgument(command, _):
            return "Missing argument for '\(command)'"
        case .unsupportedEllipticalArc:
            return "Elliptical arcs are not supported"
        }
    }
}

struct SVGPath {
    public let commands: [SVGCommand]

    public init(_ string: String) throws {
        var token: UnicodeScalar = "z"
        var commands = [SVGCommand]()
        var numbers = [CGFloat]()
        var number = ""
        var isRelative = false

        func assertArgs(_ count: Int) throws {
            if numbers.count > count {
                throw SVGErrorType
                    .unexpectedArgument(for: String(token), expected: count)
            } else if numbers.count < count {
                throw SVGErrorType
                    .missingArgument(for: String(token), expected: count)
            }
        }

        func moveTo() throws -> SVGCommand {
            try assertArgs(2)
            return .moveTo(CGPoint(x: numbers[0], y: -numbers[1]))
        }

        func lineTo() throws -> SVGCommand {
            try assertArgs(2)
            return .lineTo(CGPoint(x: numbers[0], y: -numbers[1]))
        }

        func lineToVertical() throws -> SVGCommand {
            try assertArgs(1)
            return .lineTo(CGPoint(
                x: isRelative ? 0 : (commands.last?.point.x ?? 0),
                y: -numbers[0]
            ))
        }

        func lineToHorizontal() throws -> SVGCommand {
            try assertArgs(1)
            return .lineTo(CGPoint(
                x: numbers[0],
                y: isRelative ? 0 : (commands.last?.point.y ?? 0)
            ))
        }

        func quadCurve() throws -> SVGCommand {
            try assertArgs(4)
            return .quadratic(
                CGPoint(x: numbers[0], y: -numbers[1]),
                CGPoint(x: numbers[2], y: -numbers[3])
            )
        }

        func quadTo() throws -> SVGCommand {
            try assertArgs(2)
            var lastControl = commands.last?.control1 ?? .zero
            let lastPoint = commands.last?.point ?? .zero
            if case .quadratic? = commands.last {} else {
                lastControl = lastPoint
            }
            var control = lastPoint - lastControl
            if !isRelative {
                control = control + lastPoint
            }
            return .quadratic(control, CGPoint(x: numbers[0], y: -numbers[1]))
        }

        func cubicCurve() throws -> SVGCommand {
            try assertArgs(6)
            return .cubic(
                CGPoint(x: numbers[0], y: -numbers[1]),
                CGPoint(x: numbers[2], y: -numbers[3]),
                CGPoint(x: numbers[4], y: -numbers[5])
            )
        }

        func cubicTo() throws -> SVGCommand {
            try assertArgs(4)
            var lastControl = commands.last?.control2 ?? .zero
            let lastPoint = commands.last?.point ?? .zero
            if case .cubic? = commands.last {} else {
                lastControl = lastPoint
            }
            var control = lastPoint - lastControl
            if !isRelative {
                control = control + lastPoint
            }
            return .cubic(
                control,
                CGPoint(x: numbers[0], y: -numbers[1]),
                CGPoint(x: numbers[2], y: -numbers[3])
            )
        }

        func arc() throws -> SVGCommand {
            try assertArgs(7)
            return .arc(SVGArc(
                radius: CGSize(width: numbers[0], height: numbers[1]),
                rotation: numbers[2] * .pi / 180,
                largeArc: numbers[3] != 0,
                sweep: numbers[4] != 0,
                end: CGPoint(x: numbers[5], y: -numbers[6])
            ))
        }

        func end() throws -> SVGCommand {
            try assertArgs(0)
            return .end
        }

        func processNumber() throws {
            if number.isEmpty {
                return
            }
            if let double = Double(number) {
                numbers.append(CGFloat(double))
                number = ""
                return
            }
            throw SVGErrorType.unexpectedToken(number)
        }

        func processCommand() throws {
            let command: SVGCommand
            switch token {
            case "m", "M": command = try moveTo()
            case "l", "L": command = try lineTo()
            case "v", "V": command = try lineToVertical()
            case "h", "H": command = try lineToHorizontal()
            case "q", "Q": command = try quadCurve()
            case "t", "T": command = try quadTo()
            case "c", "C": command = try cubicCurve()
            case "s", "S": command = try cubicTo()
            case "a", "A": command = try arc()
            case "z", "Z": command = .end
            default: throw SVGErrorType.unexpectedToken(String(token))
            }
            let last = isRelative ? commands.last : nil
            commands.append(command.relative(to: last))
            numbers.removeAll()
        }

        for char in string.unicodeScalars {
            switch char {
            case "0" ... "9", "E", "e", "+":
                number.append(Character(char))
            case ".":
                if number.contains(".") {
                    try processNumber()
                }
                number.append(".")
            case "-":
                try processNumber()
                number = "-"
            case "a" ... "z":
                try processNumber()
                try processCommand()
                token = char
                isRelative = true
            case "A" ... "Z":
                try processNumber()
                try processCommand()
                token = char
                isRelative = false
            case " ", "\r", "\n", "\t", ",":
                try processNumber()
            default:
                throw SVGErrorType.unexpectedToken(String(char))
            }
        }
        try processNumber()
        try processCommand()
        self.commands = commands
    }
}

struct SVGArc {
    var radius: CGSize
    var rotation: CGFloat
    var largeArc: Bool
    var sweep: Bool
    var end: CGPoint

    fileprivate func relative(to last: CGPoint) -> SVGArc {
        var arc = self
        arc.end = arc.end + last
        return arc
    }
}

enum SVGCommand {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case quadratic(CGPoint, CGPoint)
    case arc(SVGArc)
    case end

    var point: CGPoint {
        switch self {
        case let .moveTo(point),
             let .lineTo(point),
             let .cubic(_, _, point),
             let .quadratic(_, point):
            return point
        case let .arc(arc):
            return arc.end
        case .end:
            return .zero
        }
    }

    var control1: CGPoint? {
        switch self {
        case let .cubic(control1, _, _), let .quadratic(control1, _):
            return control1
        case .moveTo, .lineTo, .arc, .end:
            return nil
        }
    }

    var control2: CGPoint? {
        switch self {
        case let .cubic(_, control2, _):
            return control2
        case .moveTo, .lineTo, .quadratic, .arc, .end:
            return nil
        }
    }

    fileprivate func relative(to last: SVGCommand?) -> SVGCommand {
        guard let last = last?.point else {
            return self
        }
        switch self {
        case let .moveTo(point):
            return .moveTo(point + last)
        case let .lineTo(point):
            return .lineTo(point + last)
        case let .cubic(control1, control2, point):
            return .cubic(control1 + last, control2 + last, point + last)
        case let .quadratic(control, point):
            return .quadratic(control + last, point + last)
        case let .arc(arc):
            return .arc(arc.relative(to: last))
        case .end:
            return .end
        }
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

#endif
