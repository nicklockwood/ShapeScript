//
//  FileMonitor.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 06/11/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

final class FileMonitor {
    let url: URL
    var linkedResources = Set<URL>()
    var securityScopedResources = Set<URL>()

    private var modified: TimeInterval
    private var timer: Timer?
    private var reload: (URL) throws -> Void

    init?(_ url: URL?, reload: @escaping (URL) throws -> Void) {
        guard let url, url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        self.url = url
        self.reload = reload
        self.modified = Date.timeIntervalSinceReferenceDate

        func getModifiedDate(_ url: URL) -> TimeInterval? {
            let date = (try? FileManager.default
                .attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
            return date.map(\.timeIntervalSinceReferenceDate)
        }

        func fileIsModified(_ url: URL) -> Bool {
            guard let newDate = getModifiedDate(url), newDate > modified else {
                return false
            }
            return true
        }

        self.timer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            guard let self else {
                return
            }
            guard getModifiedDate(self.url) != nil else {
                self.timer?.invalidate()
                self.timer = nil
                return
            }
            var isModified = false
            for u in [self.url] + Array(self.linkedResources) {
                isModified = isModified || fileIsModified(u)
            }
            guard isModified else {
                return
            }
            self.markUpdated()
            try? self.reload(self.url)
        }
    }

    func markUpdated() {
        modified = Date.timeIntervalSinceReferenceDate
    }

    deinit {
        timer?.invalidate()
        for resource in securityScopedResources {
            resource.stopAccessingSecurityScopedResource()
        }
    }
}
