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
            case .end:
                path.closeSubpath()
            }
        }
        return path
    }
}

enum SVGErrorType: Error {
    case unexpectedToken(String)
    case unexpectedArgument(for: String, expected: Int)
    case missingArgument(for: String, expected: Int)

    var message: String {
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
            return .lineTo(CGPoint(x: 0, y: -numbers[0]))
        }

        func lineToHorizontal() throws -> SVGCommand {
            try assertArgs(1)
            return .lineTo(CGPoint(x: numbers[0], y: 0))
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

enum SVGCommand {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case quadratic(CGPoint, CGPoint)
    case end

    var point: CGPoint {
        switch self {
        case let .moveTo(point),
             let .lineTo(point),
             let .cubic(_, _, point),
             let .quadratic(_, point):
            return point
        case .end:
            return .zero
        }
    }

    var control1: CGPoint? {
        switch self {
        case let .cubic(control1, _, _), let .quadratic(control1, _):
            return control1
        case .moveTo, .lineTo, .end:
            return nil
        }
    }

    var control2: CGPoint? {
        switch self {
        case let .cubic(_, control2, _):
            return control2
        case .moveTo, .lineTo, .quadratic, .end:
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
