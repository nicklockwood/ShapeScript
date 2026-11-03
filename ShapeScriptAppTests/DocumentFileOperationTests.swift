//
//  DocumentFileOperationTests.swift
//  ShapeScriptAppTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import Viewer
import FileProvider
import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif

struct DocumentFileOperationTests {
    @Test func duplicateNamesPreserveExtensionsAndIncrementSuffixes() {
        for (name, expected) in [
            ("Model.shape", "Model 2.shape"),
            ("Model 2.shape", "Model 3.shape"),
            ("Model 9.CSG", "Model 10.CSG"),
            ("Model2.shape", "Model2 2.shape"),
            ("Model", "Model 2"),
            ("Model 2", "Model 3"),
            ("Model.preview.svg", "Model.preview 2.svg"),
            ("Model 18446744073709551615.shape", "Model 18446744073709551615 2.shape"),
        ] {
            #expect(URL(fileURLWithPath: name).duplicateFileName == expected)
        }
    }

    @Test func successiveExportsUseIndependentSnapshotsAndCleanUp() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Model.shape")
        try Data("cube".utf8).write(to: original)
        var first: DocumentDuplicateExport? = try .init(fileURL: original, contents: Data("sphere".utf8))
        let firstURL = try #require(first?.fileURL)
        let second = try DocumentDuplicateExport(fileURL: original, contents: Data("cone".utf8))
        #expect(firstURL != second.fileURL)
        #expect(firstURL.lastPathComponent == "Model 2.shape")
        #expect(second.fileURL.lastPathComponent == "Model 2.shape")
        #expect(try Data(contentsOf: firstURL) == Data("sphere".utf8))
        #expect(try Data(contentsOf: second.fileURL) == Data("cone".utf8))
        #expect(try Data(contentsOf: original) == Data("cube".utf8))
        first = nil
        #expect(!FileManager.default.fileExists(atPath: firstURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.fileURL.path))
    }

    @Test func binaryDuplicatesPreserveBytesAndCleanupDoesNotDeleteExportedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Model.stl")
        let bytes = Data([0, 255, 128, 13, 10, 0])
        try bytes.write(to: original)
        var export: DocumentDuplicateExport? = try .init(fileURL: original, contents: nil)
        let staged = try #require(export?.fileURL)
        let destination = directory.appendingPathComponent("Copy.stl")
        try FileManager.default.moveItem(at: staged, to: destination)
        export = nil
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
    }

    @Test func renameConflictsAndCancellationDoNotShowAnotherAlert() {
        let collision = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteFileExists.rawValue)
        let providerCollision = NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.filenameCollision.rawValue
        )
        let wrapper = NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: providerCollision])
        for error in [
            collision, providerCollision, wrapper,
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteInvalidFileName.rawValue),
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.userCancelled.rawValue),
        ] {
            #expect(error.isHandledRenameError)
        }
        #expect(!NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            .isHandledRenameError)
        #expect(!NSError(domain: "Unrelated", code: collision.code).isHandledRenameError)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    #if canImport(UIKit)
    @Test @MainActor func duplicateIncludesUnsavedSourceAndPreservesDocumentState() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Model.shape")
        try Data("cube".utf8).write(to: original)
        let document = Document(fileURL: original)
        document.autosaveEnabled = false
        document.sourceString = "sphere"
        document.updateChangeCount(.done)
        let export = try document.makeDuplicateExport()
        #expect(try Data(contentsOf: export.fileURL) == Data("sphere".utf8))
        #expect(try Data(contentsOf: original) == Data("cube".utf8))
        #expect(document.hasUnsavedChanges)
        #expect(document.fileURL == original)
    }

    @Test @MainActor func concurrentDocumentReloadsComplete() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Model.shape")
        try Data("cube".utf8).write(to: url)
        let document = Document(fileURL: url)
        let opened = await document.open()
        try #require(opened)
        document.autosaveEnabled = false
        let first = Task { @MainActor in
            await withCheckedContinuation { continuation in
                document.revert(toContentsOf: url) { continuation.resume(returning: $0) }
            }
        }
        let second = Task.detached { @Sendable [document, url] in
            await withCheckedContinuation { continuation in
                document.revert(toContentsOf: url) { continuation.resume(returning: $0) }
            }
        }
        #expect(await first.value)
        #expect(await second.value)
        #expect(document.sourceString == "cube")
        #expect(await document.close())
    }
    #endif
}
