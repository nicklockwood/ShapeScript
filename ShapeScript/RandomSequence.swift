//
//  RandomSequence.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 07/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

private extension Double {
    static let modulus: Double = .init(UInt32.max) + 1
    static let multiplier: Double = 1664525
    static let increment: Double = 1013904223
}

final class RandomSequence {
    var seed: Double {
        didSet {
            seed = seed.truncatingRemainder(dividingBy: .modulus)
        }
    }

    /// create sequence with specific seed
    init(seed: Double) {
        self.seed = seed.truncatingRemainder(dividingBy: .modulus)
    }

    /// compute next seed and return value as double in range 0.0 ..< 1.0
    func next() -> Double {
        seed = seed * .multiplier + .increment
        return seed / .modulus
    }
}
