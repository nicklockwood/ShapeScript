//
//  SelectionTests.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 08/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import SceneKit
import XCTest

private typealias SelectionMockDocument = MockDocument<DocumentViewController>

@MainActor
final class SelectionTests: XCTestCase {
    func testClearingSelectionDoesNotAddEmptyGroupGeometry() throws {
        let geometry = try evaluate("group { position 10\ncube }")
        XCTAssertTrue(geometry.build { false })
        geometry.scnBuild(with: .default)
        let node = SCNNode(geometry)
        let group = try XCTUnwrap(node.childNodes.first)
        let cube = try XCTUnwrap(group.childNodes.first)
        XCTAssertNil(node.geometry)
        XCTAssertNil(group.geometry)
        XCTAssertNotNil(geometry.select(with: cube))
        XCTAssertNotNil(cube.geometry)
        _ = geometry.select(with: nil)
        XCTAssertNil(node.geometry)
        XCTAssertNil(group.geometry)
        XCTAssertEqual(node.boundingBox.min.x, 9.5, accuracy: 1e-6)
        XCTAssertEqual(node.boundingBox.max.x, 10.5, accuracy: 1e-6)
    }

    private func document(for source: String) throws -> SelectionMockDocument {
        let document = SelectionMockDocument()
        let geometry = try evaluate(source)
        document.scene = Scene(
            background: .color(.clear),
            children: geometry.children,
            cache: nil
        )
        return document
    }

    private func flattenedSelectionMenuEntries(
        for document: SelectionMockDocument
    ) -> [SelectionMenuEntry] {
        var entries = [SelectionMenuEntry]()

        func flatten(_ menuEntries: [SelectionMenuEntry]) {
            for entry in menuEntries {
                entries.append(entry)
                flatten(entry.children)
            }
        }

        flatten(document.selectionMenuEntries)
        return entries
    }

    private func isEnabledInSelectionMenu(_ entry: SelectionMenuEntry) -> Bool {
        entry.isSelectable || entry.children.contains(where: isEnabledInSelectionMenu)
    }

    func testSelectionMenuShowsButDisablesGroupsWithNoSelectableChildren() throws {
        let document = try document(for: """
        group {
            group {
                light
            }
        }
        group {
            cube
        }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "group", "group", "cube"])
        XCTAssertFalse(isEnabledInSelectionMenu(entries[0]))
        XCTAssertFalse(isEnabledInSelectionMenu(entries[1]))
        XCTAssertTrue(isEnabledInSelectionMenu(entries[2]))
        XCTAssertTrue(isEnabledInSelectionMenu(entries[3]))
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube"])
    }

    func testSelectionMenuDisablesUnfocusedGroupsWithSelectableChildren() throws {
        let document = try document(for: """
        focus group {
            cube {
                position -1.5
                color 1 0 0
            }
        }

        group {
            sphere {
                color 0 1 0
            }
        }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "cube", "group", "sphere"])
        XCTAssertTrue(isEnabledInSelectionMenu(entries[0]))
        XCTAssertTrue(entries[1].isSelectable)
        XCTAssertFalse(isEnabledInSelectionMenu(entries[2]))
        XCTAssertFalse(entries[3].isSelectable)
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube"])
    }

    func testSelectionMenuKeepsUnfocusedBranchVisibleButUnselectable() throws {
        let document = try document(for: """
        focus group {
            group {
                sphere
            }
        }
        group {
            group {
                cube
            }
        }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)

        XCTAssertEqual(
            entries.map(\.geometry.type.logDescription),
            ["group", "group", "sphere", "group", "group", "cube"]
        )
        XCTAssertTrue(entries[2].isSelectable)
        XCTAssertFalse(entries[5].isSelectable)
        XCTAssertFalse(isEnabledInSelectionMenu(entries[3]))
        XCTAssertFalse(isEnabledInSelectionMenu(entries[4]))
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "group", "sphere"])
    }

    func testSelectionWithoutFocusIncludesAllSelectableGeometry() throws {
        let document = try document(for: """
        group {
            cube
        }
        group {
            sphere
        }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)
        let focus = document.geometry.childIsFocused

        XCTAssertFalse(focus)
        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "cube", "group", "sphere"])
        XCTAssertTrue(entries.allSatisfy(isEnabledInSelectionMenu))
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube", "group", "sphere"])
    }

    func testSelectionMenuOmitsHiddenGeometry() throws {
        let document = try document(for: """
        group {
            hide cube
        }
        sphere
        """)
        let entries = flattenedSelectionMenuEntries(for: document)

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "sphere"])
        XCTAssertFalse(isEnabledInSelectionMenu(entries[0]))
        XCTAssertTrue(entries[1].isSelectable)
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["sphere"])
    }
}
