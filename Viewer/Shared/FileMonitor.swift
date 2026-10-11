//
//  FileMonitor.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 06/11/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

final class FileMonitor: @unchecked Sendable {
    private(set) var url: URL
    var linkedResources = Set<URL>()
    var securityScopedResources = Set<URL>()

    private var modified: TimeInterval
    private var timer: Timer?
    private var reload: (URL) throws -> Void
    #if os(macOS)
    private var bookmark: Data?
    #endif

    init?(_ url: URL?, reload: @escaping (URL) throws -> Void) {
        guard let url, url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        self.url = url
        self.reload = reload
        self.modified = Date.timeIntervalSinceReferenceDate
        #if os(macOS)
        self.bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func markUpdated() {
        modified = Date.timeIntervalSinceReferenceDate
    }

    func move(to url: URL) {
        #if os(macOS)
        // Renew access using the bookmark from before the move
        var bookmarkURL = url
        var isStale = false
        if let bookmark,
           let resolvedURL = try? URL(
               resolvingBookmarkData: bookmark,
               options: [.withSecurityScope, .withoutUI],
               relativeTo: nil,
               bookmarkDataIsStale: &isStale
           ), resolvedURL.standardizedFileURL == url.standardizedFileURL
        {
            if !securityScopedResources.contains(resolvedURL), resolvedURL.startAccessingSecurityScopedResource() {
                securityScopedResources.insert(resolvedURL)
            }
            bookmarkURL = resolvedURL
        }
        bookmark = (try? bookmarkURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? bookmark
        #endif
        self.url = url
        markUpdated()
        if timer == nil {
            startMonitoring()
        }
    }

    private static func getModifiedDate(_ url: URL) -> TimeInterval? {
        let date = (try? FileManager.default
            .attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
        return date.map(\.timeIntervalSinceReferenceDate)
    }

    private func fileIsModified(_ url: URL) -> Bool {
        guard let newDate = Self.getModifiedDate(url), newDate > modified else {
            return false
        }
        return true
    }

    private func checkForUpdates() {
        guard Self.getModifiedDate(url) != nil else {
            timer?.invalidate()
            timer = nil
            return
        }
        var isModified = false
        for url in [url] + Array(linkedResources) {
            isModified = isModified || fileIsModified(url)
        }
        guard isModified else {
            return
        }
        markUpdated()
        try? reload(url)
    }

    deinit {
        timer?.invalidate()
        for resource in securityScopedResources {
            resource.stopAccessingSecurityScopedResource()
        }
    }
}
