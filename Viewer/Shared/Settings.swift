//
//  Settings.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import CoreServices
import Foundation
import ShapeScript

#if canImport(UIKit)
import UIKit
#endif

let appVersion: SemanticVersion = .init(Bundle.main.object(
    forInfoDictionaryKey: "CFBundleShortVersionString"
) as! String)!

extension Notification.Name {
    static let settingsUpdated: Self = .init(rawValue: "settingsUpdated")
}

final class Settings: @unchecked Sendable {
    static let shared = Settings()

    let defaults: UserDefaults
    let diskCache: DiskCache
    var associatedData: [String: Any] = [:]

    init(defaults: UserDefaults = .standard, diskCache: DiskCache = .shared) {
        self.defaults = defaults
        self.diskCache = diskCache
        Task {
            await diskCache.setCapacity(diskCacheCapacity)
        }
    }

    // MARK: Global

    func value<T>(for key: String) -> T? {
        defaults.object(forKey: key) as? T
    }

    func set(_ value: (some Any)?, for key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: Document

    private var documentSettings = [URL: [String: Any]]()

    func value<T>(for key: String, in document: some DocumentProtocol) -> T? {
        if let url = document._fileURL {
            if let value = documentSettings[url]?[key] as? T {
                return value
            }
            if let data = try? url.xattr(for: key.xattrName), let value = data.as(T.self) {
                documentSettings[url]?[key] = value
                return value
            }
        }
        // Return global default
        return defaults.object(forKey: key) as? T
    }

    func value<T: RawRepresentable>(for key: String, in document: some DocumentProtocol) -> T? {
        let rawValue = value(for: key, in: document) as T.RawValue?
        return rawValue.flatMap(T.init(rawValue:))
    }

    func set(
        _ value: (some Any)?,
        for key: String,
        in document: some DocumentProtocol,
        andGlobally applyGlobally: Bool = false
    ) {
        if let url = document._fileURL {
            documentSettings[url, default: [:]][key] = value
            try? url.setXattr(Data(value), for: key.xattrName)
        }
        if applyGlobally {
            // Set global default
            defaults.set(value, forKey: key)
            NotificationCenter.default.post(name: .settingsUpdated, object: key)
        } else {
            defaults.set(nil, forKey: key)
        }
    }

    func set(
        _ value: (some RawRepresentable)?,
        for key: String,
        in document: some DocumentProtocol,
        andGlobally applyGlobally: Bool = false
    ) {
        set(value?.rawValue, for: key, in: document, andGlobally: applyGlobally)
    }

    // MARK: App version

    var appVersion: SemanticVersion? {
        get { (defaults.object(forKey: #function) as? String).flatMap(SemanticVersion.init(_:)) }
        set { defaults.set(newValue?.rawValue, forKey: #function) }
    }

    var previousAppVersion: SemanticVersion? {
        get { (defaults.object(forKey: #function) as? String).flatMap(SemanticVersion.init(_:)) }
        set { defaults.set(newValue?.rawValue, forKey: #function) }
    }

    // MARK: Welcome screen

    var showWelcomeScreenAtStartup: Bool {
        get { defaults.object(forKey: #function) as? Bool ?? true }
        set { defaults.set(newValue, forKey: #function) }
    }

    // MARK: Floating window

    var keepWindowInFront: Bool {
        get { defaults.object(forKey: #function) as? Bool ?? false }
        set { defaults.set(newValue, forKey: #function) }
    }

    // MARK: Disk cache

    static let kilobytes: Int = 1_000
    static let megabytes: Int = 1_000_000
    static let gigabytes: Int = 1_000_000_000

    static let diskCacheSteps: [Int] = [
        0,
        100 * megabytes,
        250 * megabytes,
        500 * megabytes,
        1 * gigabytes,
        2 * gigabytes,
        4 * gigabytes,
        8 * gigabytes,
        16 * gigabytes,
    ]

    var diskCacheCapacity: Int {
        get {
            let value = defaults.object(forKey: #function) as? Int
            return Self.nearestDiskCacheCapacityStep(to: value)
        }
        set {
            let value = Self.nearestDiskCacheCapacityStep(to: newValue)
            defaults.set(value, forKey: #function)
            Task {
                await diskCache.setCapacity(value)
                NotificationCenter.default.post(name: .settingsUpdated, object: nil)
            }
        }
    }

    func clearDiskCache() async {
        await diskCache.removeAll()
        NotificationCenter.default.post(name: .settingsUpdated, object: nil)
    }

    @MainActor
    func applyExternalCacheSettings() async {
        let shouldClear = defaults.bool(forKey: "clearDiskCache")
        // Consume before suspending so simultaneous scene activations cannot clear twice.
        if shouldClear {
            defaults.set(false, forKey: "clearDiskCache")
        }
        await diskCache.setCapacity(diskCacheCapacity)
        if shouldClear {
            await clearDiskCache()
        }
    }

    var diskCacheUsage: Int {
        get async { diskCache.currentUsage }
    }

    private static func nearestDiskCacheCapacityStep(to value: Int?) -> Int {
        value.flatMap { value in
            diskCacheSteps.min {
                abs($0 - value) < abs($1 - value)
            }
        } ?? DiskCache.shared.capacity
    }

    static func formattedCacheSize(_ bytes: Int) -> String {
        if bytes == 0 {
            return "Off"
        }
        if bytes < Settings.gigabytes {
            return "\(bytes / Settings.megabytes) MB"
        }
        return "\(bytes / Settings.gigabytes) GB"
    }

    static func formattedCacheUsage(_ bytes: Int) -> String {
        func roundedUp(_ value: Int, to unit: Int) -> Int {
            (value + unit - 1) / unit
        }

        switch bytes {
        case ..<megabytes:
            return "\(roundedUp(bytes, to: kilobytes)) KB"
        case ..<gigabytes:
            return String(format: "%.1f MB", Double(bytes) / Double(megabytes))
        default:
            return String(format: "%.1f GB", Double(bytes) / Double(gigabytes))
        }
    }
}

private extension DocumentProtocol {
    var _fileURL: URL? { documentFileURL }
}

private extension URL {
    func xattr(for name: String) throws -> Data? {
        try withUnsafeFileSystemRepresentation { path -> Data? in
            let length = getxattr(path, name, nil, 0, 0, 0)
            guard length > -1 else {
                guard errno == 93 else {
                    throw posixError(errno)
                }
                return nil
            }
            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes {
                getxattr(path, name, $0.baseAddress, length, 0, 0)
            }
            guard result > -1 else {
                throw posixError(errno)
            }
            return data
        }
    }

    func setXattr(_ data: Data?, for name: String) throws {
        try withUnsafeFileSystemRepresentation { path in
            guard let data else {
                _ = removexattr(path, name, 0)
                return
            }
            let length = data.count
            let result = data.withUnsafeBytes {
                setxattr(path, name, $0.baseAddress, length, 0, 0)
            }
            guard result > -1 else {
                throw posixError(errno)
            }
        }
    }

    func posixError(_ err: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [
            NSLocalizedDescriptionKey: String(cString: strerror(err)),
        ])
    }
}

private extension Data {
    func `as`<T>(_ type: T.Type) -> T? {
        switch type {
        case is Data.Type:
            self as? T
        default:
            String(data: self, encoding: .utf8)?.as(type)
        }
    }

    init?(_ value: (some Any)?) {
        switch value {
        case let data? as Data?:
            self = data
        case let value?:
            guard let data = "\(value)".data(using: .utf8) else {
                return nil
            }
            self = data
        case nil:
            return nil
        }
    }
}

private extension String {
    var xattrName: String {
        // https://eclecticlight.co/2019/07/23/how-to-save-file-metadata
        "com.shapescript.\(self)#S"
    }

    func `as`<T>(_ type: T.Type) -> T? {
        switch type {
        case is String.Type:
            self as? T
        case is Double.Type:
            Double(self) as? T
        case is Int.Type:
            Int(self) as? T
        case is Bool.Type:
            Bool(self) as? T
        default:
            preconditionFailure("Conversion of String to \(type) is not supported")
        }
    }
}
