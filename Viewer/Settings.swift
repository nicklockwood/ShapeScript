//
//  Settings.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import CoreServices
import Foundation

final class Settings {
    static let shared = Settings()

    let defaults = UserDefaults.standard
    var associatedData: [String: Any] = [:]

    // MARK: Document

    private var documentSettings = [URL: [String: Any]]()

    func value<T>(for key: String, in document: Document) -> T? {
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

    func value<T: RawRepresentable>(for key: String, in document: Document) -> T? {
        let rawValue = value(for: key, in: document) as T.RawValue?
        return rawValue.flatMap(T.init(rawValue:))
    }

    func set<T>(_ value: T?, for key: String, in document: Document,
                andGlobally applyGlobally: Bool = false)
    {
        if let url = document._fileURL {
            documentSettings[url, default: [:]][key] = value
            try? url.setXattr(Data(value), for: key.xattrName)
        }
        if applyGlobally {
            // Set global default
            defaults.set(value, forKey: key)
        }
    }

    func set<T: RawRepresentable>(_ value: T?, for key: String, in document: Document,
                                  andGlobally applyGlobally: Bool = false)
    {
        set(value?.rawValue, for: key, in: document, andGlobally: applyGlobally)
    }
}

private extension Document {
    var _fileURL: URL? { fileURL }
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
            guard let data = data else {
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
            return self as? T
        default:
            return String(data: self, encoding: .utf8)?.as(type)
        }
    }

    init?<T>(_ value: T?) {
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
            return self as? T
        case is Double.Type:
            return Double(self) as? T
        case is Int.Type:
            return Int(self) as? T
        case is Bool.Type:
            return Bool(self) as? T
        default:
            preconditionFailure("Conversion of String to \(type) is not supported")
        }
    }
}
