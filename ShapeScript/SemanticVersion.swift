//
//  SemanticVersion.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 21/09/2025.
//  Copyright © 2025 Nick Lockwood. All rights reserved.
//

import Foundation

public struct SemanticVersion: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: some StringProtocol) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CharacterSet.decimalDigits.contains(rawValue.unicodeScalars.first ?? " ") else {
            return nil
        }
        self.rawValue = rawValue
    }
}

extension SemanticVersion: Comparable, ExpressibleByStringLiteral, LosslessStringConvertible {
    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.compare(
            rhs.rawValue,
            options: .numeric,
            locale: Locale(identifier: "en_US")
        ) == .orderedAscending
    }

    public init(stringLiteral version: String) {
        self.init(version)!
    }

    public init?(_ version: some StringProtocol) {
        self.init(rawValue: version)
    }
}
