//
//  WarningQueue.swift
//  ShapeScript Viewer
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

@MainActor
final class WarningQueue {
    struct Presentation: Equatable, Sendable {
        let id: UUID
        let message: String
        let position: Int
        let total: Int

        var text: String {
            total > 1 ? "\(position)/\(total) \(message)" : message
        }
    }

    private struct Key: Hashable {
        let message: String
        let occurrence: Int
    }

    private struct Entry {
        let id: UUID
        let key: Key
        let message: String
    }

    private var dismissed = Set<Key>()
    private var pending = [Entry]()
    private var currentIndex = 0

    nonisolated init() {}

    var current: Presentation? {
        guard pending.indices.contains(currentIndex) else { return nil }
        let entry = pending[currentIndex]
        return Presentation(
            id: entry.id,
            message: entry.message,
            position: currentIndex + 1,
            total: pending.count
        )
    }

    func update(_ messages: [String]) {
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.key, $0.id) })
        let currentKey = pending.indices.contains(currentIndex) ? pending[currentIndex].key : nil
        var seen = Set<String>()
        var occurrences = [String: Int]()
        let updated: [Entry] = messages.compactMap { message in
            guard seen.insert(message).inserted else {
                return nil
            }
            let normalized = Self.key(for: message)
            let occurrence = occurrences[normalized, default: 0]
            occurrences[normalized] = occurrence + 1
            // Preserve separate source occurrences without using their changing line numbers as identity.
            let key = Key(message: normalized, occurrence: occurrence)
            guard !dismissed.contains(key) else {
                return nil
            }
            return Entry(id: existing[key] ?? UUID(), key: key, message: message)
        }
        // Keep the cycle stable across reloads, appending newly introduced warnings.
        let updatedByKey = Dictionary(uniqueKeysWithValues: updated.map { ($0.key, $0) })
        pending = pending.compactMap { updatedByKey[$0.key] } + updated.filter { existing[$0.key] == nil }
        currentIndex = currentKey.flatMap { key in pending.firstIndex { $0.key == key } } ?? 0
    }

    @discardableResult
    func advance(_ id: UUID) -> Bool {
        guard current?.id == id else {
            return false
        }
        currentIndex = (currentIndex + 1) % pending.count
        return true
    }

    @discardableResult
    func dismissAll(_ id: UUID) -> Bool {
        guard current?.id == id else {
            return false
        }
        dismissed.formUnion(pending.map(\.key))
        pending.removeAll()
        currentIndex = 0
        return true
    }

    func reset() {
        dismissed.removeAll()
        pending.removeAll()
        currentIndex = 0
    }

    private static func key(for message: String) -> String {
        // Moving an existing diagnostic to another line does not introduce a new warning.
        if let range = message.range(of: #" on line \d+\.$"#, options: .regularExpression) {
            return String(message[..<range.lowerBound])
        }
        return message
    }
}
