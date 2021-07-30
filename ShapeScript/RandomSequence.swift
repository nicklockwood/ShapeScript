//
//  RandomSequence.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 07/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

final class RandomSequence {
    private static let modulus = Double(UInt32.max) + 1
    private static let multiplier = 1664525.0
    private static let increment = 1013904223.0

    private(set) var seed = 0.0 {
        didSet {
            seed = seed.truncatingRemainder(dividingBy: RandomSequence.modulus)
        }
    }

    // create sequence with specific seed
    init(seed: Double) {
        self.seed = seed
    }

    // compute next seed and return value as double in range 0.0 ..< 1.0
    func next() -> Double {
        seed = seed * RandomSequence.multiplier + RandomSequence.increment
        return seed / RandomSequence.modulus
    }
}
