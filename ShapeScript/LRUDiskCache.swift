//
//  LRUDiskCache.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 24/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum LRUDiskCacheError: Error {
    case invalidKey
    case valueCannotBeEncoded
}

/// A thread-safe least-recently-used cache backed by disk.
///
/// `LRUDiskCache` persists compressed data on Apple platforms when doing so
/// reduces the stored byte size, and uncompressed data on other platforms.
/// Values are evicted least-recently-used first when the
/// disk capacity is exceeded. Reading a value with `value(forKey:)` updates
/// its recency, while `hasValue(forKey:)` does not.
///
/// Keys must conform to `Codable`. Caches can be created when `Value` conforms
/// to `Codable` or `LRUDiskCacheDataConvertible`. Disk cost is calculated from
/// the actual stored byte size.
///
/// - Parameters:
///   - Key: The type used to identify cached values.
///   - Value: The type of values stored in the cache.
public final class LRUDiskCache<Key: Hashable & Sendable & Codable, Value>: @unchecked Sendable {
    private let diskStore: DiskStore
    private let lock: NSLock = .init()

    @available(*, unavailable, message: """
    Value must conform to Codable or LRUDiskCacheDataConvertible
    """)
    public convenience init(capacity _: Int = .max, directory _: URL? = nil) {
        preconditionFailure()
    }

    private init(diskStore: DiskStore) {
        self.diskStore = diskStore
    }
}

public extension LRUDiskCache {
    /// The current total size of values on disk.
    var currentUsage: Int {
        atomic { diskStore.currentUsage }
    }

    /// The number of values currently stored in the cache.
    var count: Int {
        atomic { diskStore.count }
    }

    /// A Boolean value indicating whether the cache is empty.
    var isEmpty: Bool {
        atomic { diskStore.isEmpty }
    }

    /// The maximum size permitted on disk.
    ///
    /// Lowering this value immediately evicts least-recently-used values until
    /// the disk cache is within the new limit. Setting this value to zero
    /// removes all values from disk and disables persistence.
    var capacity: Int {
        get { atomic { diskStore.capacity } }
        set {
            atomic {
                diskStore.capacity = newValue
                diskStore.clean()
            }
        }
    }

    /// Returns whether a value exists for the specified key.
    /// Calling this method does not update the value's recency.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: `true` if a value exists for `key`, otherwise, `false`.
    func hasValue(forKey key: Key) -> Bool {
        atomic { DiskStore.Key(key).map(diskStore.hasData(forKey:)) ?? false }
    }

    /// Removes all values from disk.
    func removeAll() {
        atomic { diskStore.removeAll() }
    }

    /// Synchronizes this cache instance with values currently stored on disk.
    ///
    /// Call this when other cache instances may have written to or removed
    /// values from the same directory, and this instance needs up-to-date
    /// `count`, `isEmpty`, or `currentUsage`. If the synchronized contents exceed
    /// this cache's capacity, the least-recently-used values are removed.
    func synchronize() {
        atomic {
            diskStore.refreshFilePlaceholders()
            diskStore.clean()
        }
    }
}

public extension LRUDiskCache where Value: Codable {
    /// Creates a cache with the specified disk limit.
    ///
    /// Values are evicted least-recently-used first when capacity is exceeded.
    /// A disk capacity of zero disables persistence.
    ///
    /// - Parameters:
    ///   - capacity: The maximum size of values stored on disk. The
    ///     default is `Int.max`, which is effectively unlimited. Set this to
    ///     zero to disable disk persistence.
    ///   - directory: The directory used for disk storage. If omitted, the
    ///     cache uses a platform cache directory.
    @_disfavoredOverload
    convenience init(capacity: Int = .max, directory: URL? = nil) {
        self.init(diskStore: .init(capacity: capacity, directory: directory))
    }

    /// Inserts or removes a value for the specified key.
    ///
    /// Passing a non-`nil` value persists it on disk when disk persistence is
    /// enabled and marks it as most recently used. Passing `nil` removes the
    /// value from disk.
    ///
    /// - Parameters:
    ///   - value: The value to cache, or `nil` to remove any existing value for `key`.
    ///   - key: The key used to store and retrieve the value.
    @_disfavoredOverload
    func setValue(_ value: Value?, forKey key: Key) throws {
        guard let value else {
            removeData(forKey: key)
            return
        }
        let data = try JSONEncoder().encode(value)
        try setData(data, forKey: key)
    }

    /// Returns the value for the specified key and marks it as most recently used.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value for `key`, or `nil` if no value exists.
    @_disfavoredOverload
    func value(forKey key: Key) -> Value? {
        value(forKey: key) { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    /// Removes the value for the specified key.
    ///
    /// This overload does not decode the removed value.
    ///
    /// - Parameter key: The key whose value should be removed.
    func removeValue(forKey key: Key) {
        removeData(forKey: key)
    }

    /// Removes and returns the value for the specified key.
    ///
    /// - Parameter key: The key whose value should be removed.
    /// - Returns: The value removed from memory or disk, or `nil` if no value
    ///   exists for `key`.
    @_disfavoredOverload
    func removeValue(forKey key: Key) -> Value? {
        removeValue(forKey: key) { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}

/// A type that can be stored in an `LRUDiskCache`.
public protocol LRUDiskCacheDataConvertible {
    /// Creates a value from its disk cache representation.
    ///
    /// - Parameter data: The raw data stored by the disk cache.
    init?(data: Data)

    /// The value's disk cache representation.
    var data: Data? { get }
}

extension Data: LRUDiskCacheDataConvertible {
    public init?(data: Data) {
        self = data
    }

    public var data: Data? {
        self
    }
}

extension String: LRUDiskCacheDataConvertible {
    public init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }

    public var data: Data? {
        data(using: .utf8)
    }
}

#if canImport(UIKit)

extension UIImage: LRUDiskCacheDataConvertible {
    public var data: Data? {
        pngData()
    }
}

#elseif canImport(AppKit)

extension NSImage: LRUDiskCacheDataConvertible {
    public var data: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

#endif

public extension LRUDiskCache where Value: LRUDiskCacheDataConvertible {
    /// Creates a cache with the specified disk limit.
    ///
    /// Values are evicted least-recently-used first when capacity is exceeded.
    /// A disk capacity of zero disables persistence.
    ///
    /// - Parameters:
    ///   - capacity: The maximum size of values stored on disk. The
    ///     default is `Int.max`, which is effectively unlimited. Set this to
    ///     zero to disable disk persistence.
    ///   - directory: The directory used for disk storage. If omitted, the
    ///     cache uses a platform cache directory.
    convenience init(capacity: Int = .max, directory: URL? = nil) {
        self.init(diskStore: .init(capacity: capacity, directory: directory))
    }

    /// Inserts or removes a value for the specified key.
    ///
    /// Passing a non-`nil` value persists it on disk when disk persistence is
    /// enabled and marks it as most recently used. Passing `nil` removes the
    /// value from disk.
    ///
    /// - Parameters:
    ///   - value: The value to cache, or `nil` to remove any existing value for `key`.
    ///   - key: The key used to store and retrieve the value.
    func setValue(_ value: Value?, forKey key: Key) throws {
        guard let value else {
            removeData(forKey: key)
            return
        }
        guard let data = value.data else {
            throw LRUDiskCacheError.valueCannotBeEncoded
        }
        try setData(data, forKey: key)
    }

    /// Returns the value for the specified key and marks it as most recently used.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value for `key`, or `nil` if no value exists.
    func value(forKey key: Key) -> Value? {
        value(forKey: key, decode: Value.init(data:))
    }

    /// Removes the value for the specified key.
    ///
    /// This overload does not decode the removed value.
    ///
    /// - Parameter key: The key whose value should be removed.
    func removeValue(forKey key: Key) {
        removeData(forKey: key)
    }

    /// Removes and returns the value for the specified key.
    ///
    /// - Parameter key: The key whose value should be removed.
    /// - Returns: The value removed from memory or disk, or `nil` if no value
    ///   exists for `key`.
    @_disfavoredOverload
    func removeValue(forKey key: Key) -> Value? {
        removeValue(forKey: key, decode: Value.init(data:))
    }
}

public extension LRUDiskCache where Value: Codable & LRUDiskCacheDataConvertible {
    /// Removes the value for the specified key.
    ///
    /// This overload does not decode the removed value.
    ///
    /// - Parameter key: The key whose value should be removed.
    func removeValue(forKey key: Key) {
        removeData(forKey: key)
    }

    /// Removes and returns the value for the specified key.
    ///
    /// - Parameter key: The key whose value should be removed.
    /// - Returns: The value removed from memory or disk, or `nil` if no value
    ///   exists for `key`.
    @_disfavoredOverload
    func removeValue(forKey key: Key) -> Value? {
        removeValue(forKey: key, decode: Value.init(data:))
    }
}

private extension LRUDiskCache {
    func atomic<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try action()
    }

    func setData(_ data: Data, forKey key: Key) throws {
        try atomic {
            guard let identity = DiskStore.Key(key) else {
                throw LRUDiskCacheError.invalidKey
            }
            try diskStore.storeData(data, for: identity)
        }
    }

    func value(forKey key: Key, decode: (Data) -> Value?) -> Value? {
        atomic {
            guard let identity = DiskStore.Key(key),
                  let data = diskStore.data(forKey: identity),
                  let value = decode(data)
            else {
                return nil
            }
            return value
        }
    }

    func removeValue(forKey key: Key, decode: (Data) -> Value?) -> Value? {
        atomic {
            guard let identity = DiskStore.Key(key),
                  let data = diskStore.data(forKey: identity)
            else {
                return nil
            }
            diskStore.removeData(forKey: identity)
            return decode(data)
        }
    }

    func removeData(forKey key: Key) {
        atomic {
            guard let key = DiskStore.Key(key) else {
                return
            }
            diskStore.removeData(forKey: key)
        }
    }
}

private final class DiskStore {
    struct Key: Codable, Equatable {
        let keyData: Data
        let filename: String

        private enum CodingKeys: CodingKey {
            case keyData
        }

        init?(_ key: some Encodable) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let keyData = try? encoder.encode(key) else {
                return nil
            }
            self.init(keyData: keyData)
        }

        init(keyData: Data) {
            self.keyData = keyData
            // Keep filenames comfortably below filesystem component limits. The
            // full encoded key is stored in the cache file and checked on read.
            var hash1: UInt64 = 0xCBF29CE484222325
            var hash2: UInt64 = 0x84222325CBF29CE4
            for byte in keyData {
                hash1 ^= UInt64(byte)
                hash1 &*= 0x100000001B3
                hash2 ^= UInt64(byte) &+ 0x9E3779B97F4A7C15
                hash2 &*= 0x100000001B3
            }
            self.filename = String(format: "%016llx%016llx", hash1, hash2)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(keyData: container.decode(Data.self, forKey: .keyData))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keyData, forKey: .keyData)
        }
    }

    struct Entry {
        var key: Key?
        var cost: Int
        var lastAccessed: Date
    }

    struct CacheFile {
        var key: Key
        var data: Data
    }

    let directory: URL
    var capacity: Int
    private var entries: [String: Entry] = [:]
    private(set) var currentUsage = 0

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    init(capacity: Int, directory: URL?) {
        let directory = directory ?? Self.defaultDirectory
        self.directory = directory
        self.capacity = capacity
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        refreshFilePlaceholders()
        clean()
    }

    func storeData(_ data: Data, for key: Key) throws {
        guard capacity > 0 else {
            return
        }

        let oldCost = entries[key.filename]?.cost ?? 0
        let url = url(forFilename: key.filename)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storedData = Self.storedData(forKey: key, data: data)
        try storedData.write(to: url, options: .atomic)

        entries[key.filename] = Entry(
            key: key,
            cost: storedData.count,
            lastAccessed: Date()
        )
        currentUsage += storedData.count - oldCost
        clean()
    }

    func hasData(forKey key: Key) -> Bool {
        guard let entry = entries[key.filename] else {
            return false
        }
        return entry.key.map { $0 == key } ?? true
    }

    func data(forKey key: Key) -> Data? {
        guard hasData(forKey: key) else {
            return nil
        }
        guard let file = cacheFile(forFilename: key.filename) else {
            removeEntry(forFilename: key.filename)
            return nil
        }
        guard file.key == key else {
            return nil
        }
        touchData(forFilename: key.filename, key: file.key)
        return file.data
    }

    func removeData(forKey key: Key) {
        guard let entry = entries[key.filename] else {
            return
        }
        if let entryKey = entry.key {
            guard entryKey == key else {
                return
            }
        } else {
            guard let file = cacheFile(forFilename: key.filename),
                  file.key == key
            else {
                return
            }
        }
        removeEntry(forFilename: key.filename)
    }

    func removeAll() {
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for url in urls where isCacheFileURL(url) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        for filename in entries.keys {
            try? FileManager.default.removeItem(at: url(forFilename: filename))
        }
        entries.removeAll()
        currentUsage = 0
    }

    func clean() {
        if capacity <= 0 {
            removeAll()
            return
        }

        while currentUsage > capacity, let entry = entries.min(by: {
            $0.value.lastAccessed < $1.value.lastAccessed
        }) {
            removeEntry(forFilename: entry.key)
        }
    }

    func refreshFilePlaceholders() {
        guard capacity > 0, let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
        ) else {
            return
        }

        var filenames = Set<String>()
        for url in urls where isCacheFileURL(url) {
            filenames.insert(url.lastPathComponent)
            refreshEntry(for: url)
        }

        for filename in entries.keys where !filenames.contains(filename) {
            if let entry = entries.removeValue(forKey: filename) {
                currentUsage -= entry.cost
            }
        }
    }

    private static var defaultDirectory: URL {
        var directory = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        #if !(os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
        directory = directory.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
            isDirectory: true
        )
        #endif
        return directory.appendingPathComponent("LRUDiskCache", isDirectory: true)
    }

    private func cacheFile(forFilename filename: String) -> CacheFile? {
        guard let storedData = try? Data(contentsOf: url(forFilename: filename)),
              let file = Self.cacheFile(fromStoredData: storedData)
        else {
            return nil
        }
        return file
    }

    private func refreshEntry(forFilename filename: String) {
        refreshEntry(for: url(forFilename: filename))
    }

    private func refreshEntry(for url: URL) {
        let filename = url.lastPathComponent
        guard isCacheFileURL(url),
              let values = try? url.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .fileSizeKey,
                  .contentModificationDateKey,
              ]),
              values.isRegularFile == true,
              let cost = values.fileSize
        else {
            if let entry = entries.removeValue(forKey: filename) {
                currentUsage -= entry.cost
            }
            return
        }

        var entry = entries[filename] ?? Entry(key: nil, cost: 0, lastAccessed: .distantPast)
        currentUsage += cost - entry.cost
        entry.cost = cost
        entry.lastAccessed = values.contentModificationDate ?? .distantPast
        entries[filename] = entry
    }

    private func touchData(forFilename filename: String, key: Key) {
        let url = url(forFilename: filename)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        var entry = entries[filename] ?? Entry(key: key, cost: 0, lastAccessed: .distantPast)
        if let cost = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            currentUsage += cost - entry.cost
            entry.cost = cost
        }
        entry.key = key
        entry.lastAccessed = Date()
        entries[filename] = entry
    }

    private func removeEntry(forFilename filename: String) {
        guard let entry = entries.removeValue(forKey: filename) else {
            return
        }
        currentUsage -= entry.cost
        try? FileManager.default.removeItem(at: url(forFilename: filename))
    }

    private func url(forFilename filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    private func isCacheFileURL(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        guard !filename.hasPrefix(".") else {
            return false
        }
        return filename.count == 32 && filename.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }

    private static let cacheFileHeader = Data([
        0x53, 0x53, 0x44, 0x43, 0x46, 0x31, // SSDCF1
    ])

    private static func storedData(forKey key: Key, data: Data) -> Data {
        var file = cacheFileHeader
        append(UInt32(key.keyData.count), to: &file)
        file.append(key.keyData)
        append(UInt64(data.count), to: &file)
        file.append(data)
        return storedData(file)
    }

    private static let compressedDataHeader = Data([
        0x53, 0x53, 0x44, 0x43, 0x5A, 0x31, // SSDCZ1
    ])

    private static func storedData(_ data: Data) -> Data {
        #if canImport(Darwin)
        let shouldCompress = data.starts(with: compressedDataHeader)
        guard let compressedData = try? (data as NSData).compressed(using: .zlib) as Data else {
            return data
        }
        let storedData = compressedDataHeader + compressedData
        return shouldCompress || storedData.count < data.count ? storedData : data
        #else
        return data
        #endif
    }

    private static func data(fromStoredData storedData: Data) -> Data? {
        let data: Data
        if storedData.starts(with: compressedDataHeader) {
            #if canImport(Darwin)
            let compressedData = storedData.dropFirst(compressedDataHeader.count)
            guard let decompressed = try? (Data(compressedData) as NSData)
                .decompressed(using: .zlib) as Data
            else {
                return nil
            }
            data = decompressed
            #else
            // Compressed entries from Apple platforms are treated as cache misses.
            return nil
            #endif
        } else {
            data = storedData
        }
        guard data.starts(with: cacheFileHeader) else {
            return nil
        }
        return Data(data.dropFirst(cacheFileHeader.count))
    }

    private static func cacheFile(fromStoredData storedData: Data) -> CacheFile? {
        guard let data = data(fromStoredData: storedData) else {
            return nil
        }

        var offset = 0
        guard let keyLength: UInt32 = readInteger(from: data, offset: &offset),
              data.count - offset >= Int(keyLength)
        else {
            return nil
        }
        let keyData = data[offset ..< offset + Int(keyLength)]
        offset += Int(keyLength)

        guard let payloadLength: UInt64 = readInteger(from: data, offset: &offset),
              payloadLength <= UInt64(Int.max),
              data.count - offset == Int(payloadLength)
        else {
            return nil
        }
        let payloadData = data[offset ..< offset + Int(payloadLength)]
        return CacheFile(
            key: Key(keyData: Data(keyData)),
            data: Data(payloadData)
        )
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) {
            data.append(contentsOf: $0)
        }
    }

    private static func readInteger<T: FixedWidthInteger>(
        from data: Data,
        offset: inout Int
    ) -> T? {
        let byteCount = MemoryLayout<T>.size
        guard data.count - offset >= byteCount else {
            return nil
        }
        let value = data[offset ..< offset + byteCount].reduce(T.zero) {
            ($0 << 8) | T($1)
        }
        offset += byteCount
        return value
    }
}
