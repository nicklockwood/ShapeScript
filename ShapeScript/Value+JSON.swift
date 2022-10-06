//
//  Value+JSON.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 08/10/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

extension Value {
    init(json: Any) {
        switch json {
        case let array as [Any]:
            self = .tuple(array.map(Value.init(json:)))
        case let object as [String: Any]:
            self = .tuple(object.sorted(by: { $0.0 < $1.0 }).map {
                [.string($0), Value(json: $1)]
            })
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
