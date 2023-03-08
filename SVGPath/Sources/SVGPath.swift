//
//  SVGPath.swift
//  SVGPath
//
//  Created by Nick Lockwood on 27/09/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SVGPath
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Foundation

public struct SVGPath: Hashable {
    public var commands: [SVGCommand]

    public init(commands: [SVGCommand]) {
        self.commands = commands
    }

    public init(string: String) throws {
        var token: UnicodeScalar = " "
        var commands = [SVGCommand]()
        var numbers = ArraySlice<Double>()
        var number = ""
        var isRelative = false

        func assertArgs(_ count: Int) throws -> [Double] {
            if numbers.count < count {
                throw SVGError
                    .missingArgument(for: String(token), expected: count)
            } else if !numbers.count.isMultiple(of: count) {
                throw SVGError
                    .unexpectedArgument(for: String(token), expected: count)
            }
            defer { numbers.removeFirst(count) }
            return Array(numbers.prefix(count))
        }

        func moveTo() throws -> SVGCommand {
            let numbers = try assertArgs(2)
            return .moveTo(SVGPoint(x: numbers[0], y: -numbers[1]))
        }

        func lineTo() throws -> SVGCommand {
            let numbers = try assertArgs(2)
            return .lineTo(SVGPoint(x: numbers[0], y: -numbers[1]))
        }

        func lineToVertical() throws -> SVGCommand {
            let numbers = try assertArgs(1)
            return .lineTo(SVGPoint(
                x: isRelative ? 0 : commands.lastPoint.x,
                y: -numbers[0]
            ))
        }

        func lineToHorizontal() throws -> SVGCommand {
            let numbers = try assertArgs(1)
            return .lineTo(SVGPoint(
                x: numbers[0],
                y: isRelative ? 0 : commands.lastPoint.y
            ))
        }

        func quadCurve() throws -> SVGCommand {
            let numbers = try assertArgs(4)
            return .quadratic(
                SVGPoint(x: numbers[0], y: -numbers[1]),
                SVGPoint(x: numbers[2], y: -numbers[3])
            )
        }

        func quadTo() throws -> SVGCommand {
            let numbers = try assertArgs(2)
            var lastControl = commands.last?.control1 ?? .zero
            let lastPoint = commands.last?.point ?? .zero
            if case .quadratic? = commands.last {} else {
                lastControl = lastPoint
            }
            var control = lastPoint - lastControl
            if !isRelative {
                control = control + lastPoint
            }
            return .quadratic(control, SVGPoint(x: numbers[0], y: -numbers[1]))
        }

        func cubicCurve() throws -> SVGCommand {
            let numbers = try assertArgs(6)
            return .cubic(
                SVGPoint(x: numbers[0], y: -numbers[1]),
                SVGPoint(x: numbers[2], y: -numbers[3]),
                SVGPoint(x: numbers[4], y: -numbers[5])
            )
        }

        func cubicTo() throws -> SVGCommand {
            let numbers = try assertArgs(4)
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
                SVGPoint(x: numbers[0], y: -numbers[1]),
                SVGPoint(x: numbers[2], y: -numbers[3])
            )
        }

        func arc() throws -> SVGCommand {
            let numbers = try assertArgs(7)
            return .arc(SVGArc(
                radius: SVGPoint(x: numbers[0], y: numbers[1]),
                rotation: numbers[2] * .pi / 180,
                largeArc: numbers[3] != 0,
                sweep: numbers[4] != 0,
                end: SVGPoint(x: numbers[5], y: -numbers[6])
            ))
        }

        func end() throws -> SVGCommand {
            _ = try assertArgs(0)
            return .end
        }

        func processNumber() throws {
            if number.isEmpty {
                return
            }
            if let double = Double(number) {
                numbers.append(double)
                number = ""
                return
            }
            throw SVGError.unexpectedToken(number)
        }

        func appendCommand(_ command: SVGCommand) {
            commands.append(
                isRelative ? command.relative(to: commands.lastPoint) : command
            )
        }

        func processCommand() throws {
            let command: SVGCommand
            switch token {
            case "m", "M":
                command = try moveTo()
                if !numbers.isEmpty {
                    appendCommand(command)
                    token = UnicodeScalar(token.value - 1)!
                    return try processCommand()
                }
            case "l", "L": command = try lineTo()
            case "v", "V": command = try lineToVertical()
            case "h", "H": command = try lineToHorizontal()
            case "q", "Q": command = try quadCurve()
            case "t", "T": command = try quadTo()
            case "c", "C": command = try cubicCurve()
            case "s", "S": command = try cubicTo()
            case "a", "A": command = try arc()
            case "z", "Z": command = try end()
            case " ": return
            default: throw SVGError.unexpectedToken(String(token))
            }
            appendCommand(command)
            if !numbers.isEmpty {
                try processCommand()
            }
        }

        for char in string.unicodeScalars {
            switch char {
            case "0" ... "9", "E", "e":
                number.append(Character(char))
            case ".":
                if number.contains(".") {
                    try processNumber()
                }
                number.append(".")
            case "-", "+":
                if let last = number.last, !"eE".contains(last) {
                    try processNumber()
                }
                number.append(Character(char))
            case "a" ... "z", "A" ... "Z":
                try processNumber()
                try processCommand()
                token = char
                isRelative = char > "Z"
            case " ", "\r", "\n", "\t", ",":
                try processNumber()
            default:
                throw SVGError.unexpectedToken(String(char))
            }
        }
        try processNumber()
        try processCommand()
        self.commands = commands
    }
}

public extension SVGPath {
    func getPoints(_ points: inout [SVGPoint], detail: Int) {
        for command in commands {
            command.getPoints(&points, detail: detail)
        }
    }

    func points(withDetail detail: Int) -> [SVGPoint] {
        var points = [SVGPoint]()
        getPoints(&points, detail: detail)
        return points
    }

    struct WriteOptions {
        public static let `default` = Self()

        public var prettyPrinted: Bool
        public var wrapWidth: Int

        public init(prettyPrinted: Bool = true, wrapWidth: Int = .max) {
            self.prettyPrinted = prettyPrinted
            self.wrapWidth = wrapWidth
        }
    }

    func string(with options: WriteOptions) -> String {
        var output = ""
        var width = 0

        func append(_ string: String) {
            let spaced = width > 0 && (
                options.prettyPrinted ||
                    (string.first?.isDigit ?? false) &&
                    (output.last?.isDigit ?? false)
            )

            let w = string.count
            if width + w + (spaced ? 1 : 0) > options.wrapWidth {
                output += "\n"
                width = 0
            } else if spaced {
                output += " "
                width += 1
            }
            output += string
            width += w
        }

        func append(_ cmd: String, _ numbers: Double...) {
            append("\(cmd)\(String(format: "%g", numbers[0]))")
            numbers.dropFirst().forEach { append(String(format: "%g", $0)) }
        }

        for command in commands {
            switch command {
            case let .moveTo(point):
                append("M", point.x, -point.y)
            case let .lineTo(point):
                append("L", point.x, -point.y)
            case let .cubic(c1, c2, point):
                append("C", c1.x, -c1.y, c2.x, -c2.y, point.x, -point.y)
            case let .quadratic(control, point):
                append("Q", control.x, -control.y, point.x, -point.y)
            case let .arc(arc):
                let rad = arc.radius, end = arc.end
                let rot = arc.rotation / .pi * 180
                let large = arc.largeArc ? 1.0 : 0
                let sweep = arc.sweep ? 1.0 : 0
                append("A", rad.x, rad.y, rot, large, sweep, end.x, -end.y)
            case .end:
                append("Z")
            }
        }
        return output
    }
}

private extension Character {
    var isDigit: Bool {
        isASCII && isWholeNumber
    }
}

private extension Array where Element == SVGCommand {
    var lastPoint: SVGPoint {
        for command in reversed() {
            if let point = command.point {
                return point
            }
        }
        return .zero
    }
}

public enum SVGError: Error, Hashable {
    case unexpectedToken(String)
    case unexpectedArgument(for: String, expected: Int)
    case missingArgument(for: String, expected: Int)

    public var message: String {
        switch self {
        case let .unexpectedToken(string):
            return "Unexpected token '\(string)'"
        case let .unexpectedArgument(command, _):
            return "Too many arguments for '\(command)'"
        case let .missingArgument(command, _):
            return "Missing argument for '\(command)'"
        }
    }
}

public enum SVGCommand: Hashable {
    case moveTo(SVGPoint)
    case lineTo(SVGPoint)
    case cubic(SVGPoint, SVGPoint, SVGPoint)
    case quadratic(SVGPoint, SVGPoint)
    case arc(SVGArc)
    case end
}

public extension SVGCommand {
    var point: SVGPoint? {
        switch self {
        case let .moveTo(point),
             let .lineTo(point),
             let .cubic(_, _, point),
             let .quadratic(_, point):
            return point
        case let .arc(arc):
            return arc.end
        case .end:
            return nil
        }
    }

    var control1: SVGPoint? {
        switch self {
        case let .cubic(control1, _, _), let .quadratic(control1, _):
            return control1
        case .moveTo, .lineTo, .arc, .end:
            return nil
        }
    }

    var control2: SVGPoint? {
        switch self {
        case let .cubic(_, control2, _):
            return control2
        case .moveTo, .lineTo, .quadratic, .arc, .end:
            return nil
        }
    }

    func getPoints(_ points: inout [SVGPoint], detail: Int) {
        var start: Int?
        for (i, point) in points.enumerated() {
            if let j = start {
                if points[j] == point {
                    start = nil
                }
            } else {
                start = i
            }
        }

        func endSubpath() {
            if start == points.count - 1 {
                points.removeLast()
            } else if let start = start {
                points.append(points[start])
            }
        }

        let popLast = start != nil
        let last = points.last ?? .zero

        switch self {
        case let .moveTo(point):
            endSubpath()
            points.append(point)
        case let .lineTo(point):
            if !popLast {
                points.append(last)
            }
            points.append(point)
        case let .cubic(control1, control2, point):
            if popLast {
                _ = points.popLast()
            }
            let step = 1.0 / Double(detail)
            for t in stride(from: 0, through: 1.0, by: step) {
                points.append(SVGPoint(
                    x: cubicBezier(last.x, control1.x, control2.x, point.x, t),
                    y: cubicBezier(last.y, control1.y, control2.y, point.y, t)
                ))
            }
        case let .quadratic(control, point):
            if popLast {
                _ = points.popLast()
            }
            let step = 1.0 / Double(detail)
            for t in stride(from: 0, through: 1.0, by: step) {
                points.append(SVGPoint(
                    x: quadraticBezier(last.x, control.x, point.x, t),
                    y: quadraticBezier(last.y, control.y, point.y, t)
                ))
            }
        case let .arc(arc):
            for command in arc.asBezierPath(from: last) {
                command.getPoints(&points, detail: detail)
            }
        case .end:
            endSubpath()
        }
    }

    fileprivate func relative(to last: SVGPoint) -> SVGCommand {
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

public struct SVGPoint: Hashable {
    public var x, y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public extension SVGPoint {
    static let zero = SVGPoint(x: 0, y: 0)

    static func + (lhs: SVGPoint, rhs: SVGPoint) -> SVGPoint {
        SVGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: SVGPoint, rhs: SVGPoint) -> SVGPoint {
        SVGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

public struct SVGArc: Hashable {
    public var radius: SVGPoint
    public var rotation: Double
    public var largeArc: Bool
    public var sweep: Bool
    public var end: SVGPoint
}

public extension SVGArc {
    func asBezierPath(from currentPoint: SVGPoint) -> [SVGCommand] {
        let px = currentPoint.x, py = currentPoint.y
        var rx = abs(radius.x), ry = abs(radius.y)
        let xr = rotation
        let largeArcFlag = largeArc
        let sweepFlag = sweep
        let cx = end.x, cy = end.y
        let sinphi = sin(xr), cosphi = cos(xr)

        let dx = (px - cx) / 2, dy = (py - cy) / 2
        let pxp = cosphi * dx + sinphi * dy, pyp = -sinphi * dx + cosphi * dy
        if pxp == 0, pyp == 0 {
            return []
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

        func vectorAngle(
            _ ux: Double, _ uy: Double,
            _ vx: Double, _ vy: Double
        ) -> Double {
            let sign = (ux * vy - uy * vx < 0) ? -1.0 : 1.0
            let umag = sqrt(ux * ux + uy * uy), vmag = sqrt(vx * vx + vy * vy)
            let dot = ux * vx + uy * vy
            return sign * acos(max(-1, min(1, dot / (umag * vmag))))
        }

        func toEllipse(_ x: Double, _ y: Double) -> SVGPoint {
            let x = x * rx, y = y * ry
            let xp = cosphi * x - sinphi * y, yp = sinphi * x + cosphi * y
            return SVGPoint(x: xp + centerx, y: yp + centery)
        }

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
        return (0 ..< Int(segments)).map { _ in
            let x1 = cos(a1), y1 = sin(a1)
            let x2 = cos(a1 + a2), y2 = sin(a1 + a2)

            let p1 = toEllipse(x1 - y1 * a, y1 + x1 * a)
            let p2 = toEllipse(x2 + y2 * a, y2 - x2 * a)
            let p = toEllipse(x2, y2)

            a1 += a2
            return SVGCommand.cubic(p1, p2, p)
        }
    }

    fileprivate func relative(to last: SVGPoint) -> SVGArc {
        var arc = self
        arc.end = arc.end + last
        return arc
    }
}

private func quadraticBezier(
    _ p0: Double,
    _ p1: Double,
    _ p2: Double,
    _ t: Double
) -> Double {
    let oneMinusT = 1 - t
    let c0 = oneMinusT * oneMinusT * p0
    let c1 = 2 * oneMinusT * t * p1
    let c2 = t * t * p2
    return c0 + c1 + c2
}

private func cubicBezier(
    _ p0: Double,
    _ p1: Double,
    _ p2: Double,
    _ p3: Double,
    _ t: Double
) -> Double {
    let oneMinusT = 1 - t
    let oneMinusTSquared = oneMinusT * oneMinusT
    let c0 = oneMinusTSquared * oneMinusT * p0
    let c1 = 3 * oneMinusTSquared * t * p1
    let c2 = 3 * oneMinusT * t * t * p2
    let c3 = t * t * t * p3
    return c0 + c1 + c2 + c3
}
