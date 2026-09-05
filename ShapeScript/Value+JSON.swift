//
//  Value+JSON.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 08/10/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

extension Value {
    init(scriptOption value: Any) throws {
        switch value {
        case let array as [Any]:
            self = try .tuple(array.map(Value.init(scriptOption:)))
        case let object as [String: Any]:
            self = try .object(object.mapValues(Value.init(scriptOption:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if number.objCType.pointee == 99 { // boolean
                self = .boolean(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .void
        default:
            throw ParserError(.custom(
                "Unsupported option value '\(value)'",
                hint: "Options must be JSON-compatible values.",
                at: nil
            ))
        }
    }

    init(jsonData: Data) throws {
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData)
            self.init(json: json)
        } catch {
            let nsError = error as NSError
            var message = nsError.userInfo["NSDebugDescription"] as? String ?? nsError.localizedDescription
            var index: String.Index?
            if let byteOffset = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                index = String(data: jsonData[0 ..< byteOffset], encoding: .utf8)?.endIndex
            }
            if index != nil, let range = message.range(of: " around line ") {
                message = String(message[..<range.lowerBound])
            }
            throw ParserError(.custom(message, hint: nil, at: index.map { $0 ..< $0 }))
        }
    }

    init(json: Any) {
        switch json {
        case let array as [Any]:
            self = .tuple(array.map(Value.init(json:)))
        case let object as [String: Any]:
            self = .object(object.mapValues(Value.init(json:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if number.objCType.pointee == 99 { // boolean
                self = .boolean(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .void
        case let value:
            assertionFailure("Unsupported JSON value \(value)")
            self = .void
        }
    }
}
