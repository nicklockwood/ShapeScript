//
//  String+Ordinals.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 09/09/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

extension String {
    var isOrdinal: Bool {
        ordinalIndex != nil
    }

    var ordinalIndex: Int? {
        indicesByOrdinal[lowercased()]
    }

    static let ordinals: [String] = {
        let ordinalsToNinth = [
            "first", "second", "third", "fourth", "fifth",
            "sixth", "seventh", "eighth", "ninth",
        ]
        var result = ordinalsToNinth + [
            "tenth",
            "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
            "sixteenth", "seventeenth", "eighteenth", "nineteenth",
        ]
        result += ["twentieth"] + ordinalsToNinth.map { "twenty\($0)" }
        result += ["thirtieth"] + ordinalsToNinth.map { "thirty\($0)" }
        result += ["fortieth"] + ordinalsToNinth.map { "forty\($0)" }
        result += ["fiftieth"] + ordinalsToNinth.map { "fifty\($0)" }
        result += ["sixtieth"] + ordinalsToNinth.map { "sixty\($0)" }
        result += ["seventieth"] + ordinalsToNinth.map { "seventy\($0)" }
        result += ["eightieth"] + ordinalsToNinth.map { "eighty\($0)" }
        result += ["ninetieth"] + ordinalsToNinth.map { "ninety\($0)" }
        return result
    }()

    static func ordinals(upTo value: Int) -> ArraySlice<String> {
        ordinals.prefix(value)
    }
}

private let indicesByOrdinal: [String: Int] = Dictionary(
    uniqueKeysWithValues: String.ordinals.enumerated().map { ($1, $0) }
)
