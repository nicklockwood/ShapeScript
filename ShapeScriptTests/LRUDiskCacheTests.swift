//
//  LRUDiskCacheTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 24/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript
import XCTest

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

final class LRUDiskCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        removeTemporaryDirectory(directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testDiskCacheReturnsStoredValues() throws {
        let cache = makeStringCache()
        try cache.setValue("one", forKey: "a")
        try cache.setValue("two", forKey: "b")

        XCTAssertEqual(cache.value(forKey: "a"), "one")
        XCTAssertEqual(cache.value(forKey: "b"), "two")
    }

    func testDiskCachePersistsAcrossCacheInstances() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("value", forKey: "key")
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertTrue(restoredCache.hasValue(forKey: "key"))
        XCTAssertEqual(restoredCache.value(forKey: "key"), "value")
    }

    func testSharedDirectoryCacheInstancesDoNotClobberEntries() throws {
        let firstCache = makeStringCache()
        let secondCache = makeStringCache()

        try firstCache.setValue("one", forKey: "a")
        try secondCache.setValue("two", forKey: "b")

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "a"), "one")
        XCTAssertEqual(restoredCache.value(forKey: "b"), "two")
    }

    func testSynchronizeCleansOverflowingValuesWrittenByOtherCacheInstances() throws {
        let firstCache = makeStringCache(capacity: 1)
        let secondCache = makeStringCache(capacity: 1024)

        try secondCache.setValue("one", forKey: "a")
        try secondCache.setValue("two", forKey: "b")

        firstCache.synchronize()

        XCTAssertLessThanOrEqual(firstCache.currentUsage, firstCache.capacity)
        XCTAssertTrue(firstCache.isEmpty)
        XCTAssertNil(secondCache.value(forKey: "a"))
        XCTAssertNil(secondCache.value(forKey: "b"))
    }

    func testDiskCachePersistsLongKeysAcrossCacheInstances() throws {
        let key = String(repeating: "long-cache-key/", count: 100)
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("value", forKey: key)
        cache = nil

        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(filenames.allSatisfy { $0.count <= 255 })

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: key), "value")
    }

    func testDiskCachePersistsKeysWithDifferentEncodingOrder() throws {
        var cache: LRUDiskCache<OrderSensitiveKey, String>? = makeCache()
        try cache?.setValue(
            "value",
            forKey: OrderSensitiveKey(value: "key", encodesValueFirst: true)
        )
        cache = nil

        let restoredCache: LRUDiskCache<OrderSensitiveKey, String> = makeCache()
        XCTAssertEqual(
            restoredCache.value(
                forKey: OrderSensitiveKey(value: "key", encodesValueFirst: false)
            ),
            "value"
        )
    }

    func testDiskCachePersistsByDefault() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("value", forKey: "key")
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), "value")
    }

    func testDiskCacheIgnoresMissingLegacyMetadata() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("value", forKey: "key")
        cache = nil

        try "ignored".write(
            to: directory.appendingPathComponent(".DS_Store"),
            atomically: true,
            encoding: .utf8
        )
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("metadata.json")
        )

        let restoredCache = makeStringCache()

        XCTAssertTrue(restoredCache.hasValue(forKey: "key"))
        XCTAssertEqual(restoredCache.value(forKey: "key"), "value")
    }

    func testDiskCacheIgnoresCorruptLegacyMetadata() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("value", forKey: "key")
        cache = nil

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("metadata.json"),
            options: .atomic
        )

        let restoredCache = makeStringCache()

        XCTAssertTrue(restoredCache.hasValue(forKey: "key"))
        XCTAssertEqual(restoredCache.value(forKey: "key"), "value")
    }

    func testDiskCacheCanBeDisabledWithZeroCapacity() throws {
        var cache: LRUDiskCache<String, String>? = makeCache(capacity: 0)
        try cache?.setValue("value", forKey: "key")
        XCTAssertEqual(cache?.count, 0)
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertFalse(restoredCache.hasValue(forKey: "key"))
        XCTAssertNil(restoredCache.value(forKey: "key"))
    }

    func testRemoveCachedValueRemovesDiskValue() throws {
        let cache = makeStringCache()
        try cache.setValue("one", forKey: "a")
        try cache.setValue("two", forKey: "b")

        cache.removeValue(forKey: "a")
        XCTAssertFalse(cache.hasValue(forKey: "a"))
        XCTAssertNil(cache.value(forKey: "a"))
    }

    func testRemoveValueReturnsDiskOnlyValue() throws {
        let cache = makeStringCache()
        try cache.setValue("one", forKey: "a")
        try cache.setValue("two", forKey: "b")

        XCTAssertEqual(cache.removeValue(forKey: "a"), "one")
        XCTAssertFalse(cache.hasValue(forKey: "a"))
    }

    func testRemoveValueWithoutUsingReturnValueDoesNotDecodeCodableValue() throws {
        CountingCodableValue.decodeCounter.reset()
        let cache: LRUDiskCache<String, CountingCodableValue> = makeCache()
        try cache.setValue(CountingCodableValue(value: "value"), forKey: "key")

        cache.removeValue(forKey: "key")

        XCTAssertEqual(CountingCodableValue.decodeCounter.count, 0)
        XCTAssertFalse(cache.hasValue(forKey: "key"))
    }

    func testRemoveValueReturnsCodableValueDecodedFromDisk() throws {
        CountingCodableValue.decodeCounter.reset()
        let cache: LRUDiskCache<String, CountingCodableValue> = makeCache()
        try cache.setValue(CountingCodableValue(value: "value"), forKey: "key")

        let value: CountingCodableValue? = cache.removeValue(forKey: "key")

        XCTAssertEqual(value, CountingCodableValue(value: "value"))
        XCTAssertEqual(CountingCodableValue.decodeCounter.count, 1)
        XCTAssertFalse(cache.hasValue(forKey: "key"))
    }

    func testRemoveValueWithoutUsingReturnValueDoesNotDecodeCustomValue() throws {
        CountingCustomValue.decodeCounter.reset()
        let cache: LRUDiskCache<String, CountingCustomValue> = makeCache()
        try cache.setValue(CountingCustomValue(value: "value"), forKey: "key")
        CountingCustomValue.decodeCounter.reset()

        cache.removeValue(forKey: "key")

        XCTAssertEqual(CountingCustomValue.decodeCounter.count, 0)
        XCTAssertFalse(cache.hasValue(forKey: "key"))
    }

    func testRemoveValueReturnsCustomValueDecodedFromDisk() throws {
        CountingCustomValue.decodeCounter.reset()
        let cache: LRUDiskCache<String, CountingCustomValue> = makeCache()
        try cache.setValue(CountingCustomValue(value: "value"), forKey: "key")
        CountingCustomValue.decodeCounter.reset()

        let value: CountingCustomValue? = cache.removeValue(forKey: "key")

        XCTAssertEqual(value, CountingCustomValue(value: "value"))
        XCTAssertEqual(CountingCustomValue.decodeCounter.count, 1)
        XCTAssertFalse(cache.hasValue(forKey: "key"))
    }

    func testDiskCacheEvictsLeastRecentlyUsedValueWhenCapacityIsExceeded() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("1234567890", forKey: "a")
        try cache?.setValue("abcdefghij", forKey: "b")
        cache?.capacity = (cache?.currentUsage ?? 1) - 1
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertFalse(restoredCache.hasValue(forKey: "a"))
        XCTAssertEqual(restoredCache.value(forKey: "b"), "abcdefghij")
    }

    func testDiskCacheEvictsLeastRecentlyUsedValueAfterAccess() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("1234567890", forKey: "a")
        try cache?.setValue("abcdefghij", forKey: "b")
        _ = cache?.value(forKey: "a")
        try cache?.setValue("klmnopqrst", forKey: "c")
        cache?.capacity = (cache?.currentUsage ?? 1) - 1
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "a"), "1234567890")
        XCTAssertFalse(restoredCache.hasValue(forKey: "b"))
        XCTAssertEqual(restoredCache.value(forKey: "c"), "klmnopqrst")
    }

    func testRemoveAllCachedValuesRemovesDiskValues() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("one", forKey: "a")
        try cache?.setValue("two", forKey: "b")
        cache?.removeAll()
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertFalse(restoredCache.hasValue(forKey: "a"))
        XCTAssertFalse(restoredCache.hasValue(forKey: "b"))
    }

    func testRemoveAllDiskRemovesValues() throws {
        let cache = makeStringCache()
        try cache.setValue("one", forKey: "a")
        cache.removeAll()

        XCTAssertNil(cache.value(forKey: "a"))
        XCTAssertEqual(cache.currentUsage, 0)

        let restoredCache = makeStringCache()
        XCTAssertFalse(restoredCache.hasValue(forKey: "a"))
    }

    func testMissingDiskFileIsPrunedOnLookup() throws {
        let cache = makeStringCache()
        try cache.setValue("one", forKey: "a")
        XCTAssertGreaterThan(cache.currentUsage, 0)

        try removeFirstCacheDataFile(in: directory)

        XCTAssertTrue(cache.hasValue(forKey: "a"))
        XCTAssertGreaterThan(cache.currentUsage, 0)
        XCTAssertGreaterThan(cache.count, 0)
        XCTAssertNil(cache.value(forKey: "a"))
        XCTAssertEqual(cache.currentUsage, 0)
        XCTAssertEqual(cache.count, 0)
    }

    func testCountIncludesDiskValues() throws {
        let cache = makeStringCache()
        try cache.setValue("33333", forKey: "c")
        try cache.setValue("11111", forKey: "a")
        try cache.setValue("22222", forKey: "b")
        XCTAssertEqual(cache.value(forKey: "c"), "33333")

        XCTAssertGreaterThan(cache.currentUsage, 0)
        XCTAssertEqual(cache.count, 3)
    }

    func testChangingDiskCapacityCleansExistingValues() throws {
        let cache = makeStringCache()
        try cache.setValue("1234567890", forKey: "a")
        try cache.setValue("abcdefghij", forKey: "b")
        cache.capacity = cache.currentUsage - 1

        XCTAssertEqual(cache.count, 1)
        XCTAssertFalse(cache.hasValue(forKey: "a"))
        XCTAssertEqual(cache.value(forKey: "b"), "abcdefghij")
    }

    func testDiskCacheStoresDataWithoutEncoding() throws {
        let data = Data([1, 2, 3, 4])
        let cache: LRUDiskCache<String, Data> = makeCache()
        try cache.setValue(data, forKey: "data")

        XCTAssertGreaterThan(cache.currentUsage, 0)
        XCTAssertEqual(cache.value(forKey: "data"), data)
    }

    func testDiskCacheStoresStringAsUTF8() throws {
        let cache = makeStringCache()
        try cache.setValue("value", forKey: "key")

        XCTAssertGreaterThan(cache.currentUsage, 0)
        XCTAssertEqual(cache.value(forKey: "key"), "value")
    }

    func testDiskCacheCompressesStoredData() throws {
        let value = String(repeating: "compressible-value-", count: 100)
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue(value, forKey: "key")

        let diskUsage = try XCTUnwrap(cache?.currentUsage)
        XCTAssertLessThan(diskUsage, value.utf8.count)
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), value)
    }

    func testDiskCacheReadsUncompressedStoredData() throws {
        var cache: LRUDiskCache<String, String>? = makeCache()
        try cache?.setValue("placeholder", forKey: "key")
        let url = try cacheDataFile(in: directory)
        try uncompressedCacheFileData(at: url).write(to: url, options: .atomic)
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), "placeholder")
    }

    #if canImport(UIKit)

    func testDiskCacheStoresUIImage() throws {
        let image = try XCTUnwrap(UIImage(data: Self.pngData))
        let cache: LRUDiskCache<String, UIImage> = makeCache()
        try cache.setValue(image, forKey: "image")

        XCTAssertNotNil(cache.value(forKey: "image"))
    }

    #endif

    #if canImport(AppKit)

    func testDiskCacheStoresNSImage() throws {
        let image = try XCTUnwrap(NSImage(data: Self.pngData))
        let cache: LRUDiskCache<String, NSImage> = makeCache()
        try cache.setValue(image, forKey: "image")

        XCTAssertNotNil(cache.value(forKey: "image"))
    }

    #endif

    func testDiskCacheUsesCustomValueEncoding() throws {
        var cache: LRUDiskCache<String, CustomValue>? = makeCache()
        try cache?.setValue(CustomValue(value: "value"), forKey: "key")
        cache = nil

        let restoredCache: LRUDiskCache<String, CustomValue> = makeCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), CustomValue(value: "value"))
    }

    func testDiskCacheUsesCodableFallbackEncoding() throws {
        var cache: LRUDiskCache<String, CodableOnlyValue>? = makeCache()
        try cache?.setValue(CodableOnlyValue(value: "value"), forKey: "key")
        cache = nil

        let restoredCache: LRUDiskCache<String, CodableOnlyValue> = makeCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), CodableOnlyValue(value: "value"))
    }

    func testDiskCachePrefersCustomEncodingOverCodableFallback() throws {
        let cache: LRUDiskCache<String, CodableCustomValue> = makeCache()
        try cache.setValue(CodableCustomValue(value: "fallback"), forKey: "key")

        XCTAssertGreaterThan(cache.currentUsage, 0)
        XCTAssertEqual(cache.value(forKey: "key"), CodableCustomValue(value: "custom"))
    }

    func testDiskCacheIgnoresLegacyMetadataDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("metadata.json"),
            withIntermediateDirectories: false
        )

        var cache: LRUDiskCache<String, String>? = makeCache()
        XCTAssertNoThrow(try cache?.setValue("value", forKey: "key"))
        XCTAssertEqual(cache?.value(forKey: "key"), "value")
        cache = nil

        let restoredCache = makeStringCache()
        XCTAssertEqual(restoredCache.value(forKey: "key"), "value")
    }

    private func makeCache<
        Key: Hashable & Sendable & Codable,
        Value: LRUDiskCacheDataConvertible
    >(capacity: Int = 1024) -> LRUDiskCache<Key, Value> {
        LRUDiskCache(capacity: capacity, directory: directory)
    }

    private func makeCache<
        Key: Hashable & Sendable & Codable,
        Value: Codable
    >(capacity: Int = 1024) -> LRUDiskCache<Key, Value> {
        LRUDiskCache(capacity: capacity, directory: directory)
    }

    private func makeStringCache(capacity: Int = 1024) -> LRUDiskCache<String, String> {
        LRUDiskCache(capacity: capacity, directory: directory)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL?) {
        guard let directory else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func removeFirstCacheDataFile(in directory: URL) throws {
        try FileManager.default.removeItem(at: cacheDataFile(in: directory))
    }

    private func cacheDataFile(in directory: URL) throws -> URL {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        guard let url = urls.first(where: { $0.lastPathComponent.count == 32 }) else {
            XCTFail("Expected cache data file")
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private func uncompressedCacheFileData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let compressedDataHeader = Data([0x53, 0x53, 0x44, 0x43, 0x5A, 0x31])
        guard data.starts(with: compressedDataHeader) else {
            return data
        }
        let compressedData = data.dropFirst(compressedDataHeader.count)
        return try (Data(compressedData) as NSData).decompressed(using: .zlib) as Data
    }

    private static let pngData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
        0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99,
        0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}

private struct CustomValue: Equatable, LRUDiskCacheDataConvertible {
    var value: String

    init(value: String) {
        self.value = value
    }

    init?(data: Data) {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        self.value = String(string.reversed())
    }

    var data: Data? {
        Data(String(value.reversed()).utf8)
    }
}

private struct CodableOnlyValue: Codable, Equatable {
    var value: String
}

private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }
}

private struct CountingCodableValue: Codable, Equatable {
    static let decodeCounter = DecodeCounter()

    var value: String

    init(value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        Self.decodeCounter.increment()
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct CountingCustomValue: Equatable, LRUDiskCacheDataConvertible {
    static let decodeCounter = DecodeCounter()

    var value: String

    init(value: String) {
        self.value = value
    }

    init?(data: Data) {
        Self.decodeCounter.increment()
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        self.value = string
    }

    var data: Data? {
        Data(value.utf8)
    }
}

private struct CodableCustomValue: Codable, Equatable, LRUDiskCacheDataConvertible {
    var value: String

    init(value: String) {
        self.value = value
    }

    init?(data: Data) {
        self.value = data == Data([1]) ? "custom" : "invalid"
    }

    var data: Data? {
        Data([1])
    }
}

private struct OrderSensitiveKey: Codable, Hashable, Sendable {
    var value: String
    var encodesValueFirst: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    init(value: String, encodesValueFirst: Bool) {
        self.value = value
        self.encodesValueFirst = encodesValueFirst
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(String.self, forKey: .value)
        self.encodesValueFirst = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if encodesValueFirst {
            try container.encode(value, forKey: .value)
            try container.encode("metadata", forKey: .metadata)
        } else {
            try container.encode("metadata", forKey: .metadata)
            try container.encode(value, forKey: .value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case metadata
        case value
    }
}
