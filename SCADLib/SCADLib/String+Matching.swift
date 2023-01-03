//
//  String+Matching.swift
//  SCADLib
//
//  Created by Nick Lockwood on 03/01/2023.
//

extension String {
    // Find best match for the string in a list of options
    func bestMatches(in options: [String]) -> [String] {
        let lowercaseQuery = lowercased()
        // Sort matches by Levenshtein edit distance
        return options
            .compactMap { option -> (String, distance: Int, commonPrefix: Int)? in
                guard option != self else { return nil }
                let lowercaseOption = option.lowercased()
                let distance = lowercaseOption.editDistance(from: lowercaseQuery)
                let commonPrefix = lowercaseOption.commonPrefix(with: lowercaseQuery)
                if commonPrefix.isEmpty, distance > lowercaseQuery.count / 2 {
                    return nil
                }
                return (option, distance, commonPrefix.count)
            }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.commonPrefix > $1.commonPrefix
                }
                return $0.distance < $1.distance
            }
            .map { $0.0 }
    }

    /// The Damerau-Levenshtein edit-distance between two strings
    func editDistance(from other: String) -> Int {
        let lhs = Array(self)
        let rhs = Array(other)
        var dist = [[Int]]()
        for i in stride(from: 0, through: lhs.count, by: 1) {
            dist.append([i])
        }
        for j in stride(from: 1, through: rhs.count, by: 1) {
            dist[0].append(j)
        }
        for i in stride(from: 1, through: lhs.count, by: 1) {
            for j in stride(from: 1, through: rhs.count, by: 1) {
                if lhs[i - 1] == rhs[j - 1] {
                    dist[i].append(dist[i - 1][j - 1])
                } else {
                    dist[i].append(Swift.min(dist[i - 1][j] + 1,
                                             dist[i][j - 1] + 1,
                                             dist[i - 1][j - 1] + 1))
                }
                if i > 1, j > 1, lhs[i - 1] == rhs[j - 2], lhs[i - 2] == rhs[j - 1] {
                    dist[i][j] = Swift.min(dist[i][j], dist[i - 2][j - 2] + 1)
                }
            }
        }
        return dist[lhs.count][rhs.count]
    }
}
