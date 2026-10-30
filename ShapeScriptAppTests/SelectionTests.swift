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

    func testSelectingGroupHighlightsDescendantsAndClearsPreviousSelection() throws {
        let geometry = try evaluate("""
        group {
            cube
            group { sphere }
        }
        cylinder
        """)
        XCTAssertTrue(geometry.build { false })
        geometry.scnBuild(with: .default)
        let root = SCNNode(geometry)
        let group = geometry.children[0]
        let cube = group.children[0]
        let nestedGroup = group.children[1]
        let sphere = nestedGroup.children[0]
        let cylinder = geometry.children[1]
        let groupNode = try XCTUnwrap(group.scnNode)
        let cubeNode = try XCTUnwrap(cube.scnNode)
        let sphereNode = try XCTUnwrap(sphere.scnNode)
        let cylinderNode = try XCTUnwrap(cylinder.scnNode)

        XCTAssertTrue(geometry.select(with: groupNode) === group)
        XCTAssertNil(groupNode.geometry)
        XCTAssertNil(nestedGroup.scnNode?.geometry)
        XCTAssertFalse(cubeNode.geometry === cube.scnGeometry)
        XCTAssertFalse(sphereNode.geometry === sphere.scnGeometry)
        XCTAssertTrue(cylinderNode.geometry === cylinder.scnGeometry)
        XCTAssertTrue(geometry.select(with: cylinderNode) === cylinder)
        XCTAssertTrue(cubeNode.geometry === cube.scnGeometry)
        XCTAssertTrue(sphereNode.geometry === sphere.scnGeometry)
        XCTAssertFalse(cylinderNode.geometry === cylinder.scnGeometry)
        XCTAssertNil(geometry.select(with: nil))
        XCTAssertTrue(cylinderNode.geometry === cylinder.scnGeometry)
        XCTAssertNil(root.geometry)
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

    func testSelectionMenuOmitsGroupsWithNoSelectableChildren() throws {
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

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "cube"])
        XCTAssertTrue(entries.allSatisfy(\.isSelectable))
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube"])
    }

    func testSelectionMenuDisablesUnfocusedGroupsWithoutSubmenus() throws {
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

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "cube", "group"])
        XCTAssertEqual(entries.map(\.isSelectable), [true, true, false])
        XCTAssertTrue(entries[2].children.isEmpty)
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube"])
    }

    func testSelectionMenuCollapsesUnfocusedBranch() throws {
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
            ["group", "group", "sphere", "group"]
        )
        XCTAssertEqual(entries.map(\.isSelectable), [true, true, true, false])
        XCTAssertTrue(entries[3].children.isEmpty)
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
        XCTAssertTrue(entries.allSatisfy(\.isSelectable))
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["group", "cube", "group", "sphere"])
    }

    func testContextMenuCanSelectGroupAndItsChildren() throws {
        let document = try document(for: """
        group {
            name "Assembly"
            cube
            sphere
        }
        """)
        let group = try XCTUnwrap(document.geometry.children.first)
        let cube = try XCTUnwrap(group.children.first)
        let entries = document.selectionMenuEntries(for: cube.selectionMenuPath(root: document.geometry))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertTrue(entry.geometry === group)
        XCTAssertTrue(entry.isSelectable)
        XCTAssertEqual(entry.children.count, 1)
        XCTAssertTrue(entry.children[0].geometry === cube)
        XCTAssertEqual(entry.submenuEntries.count, 2)
        XCTAssertTrue(entry.submenuEntries[0].geometry === group)
        XCTAssertTrue(entry.submenuEntries[0].children.isEmpty)
        XCTAssertTrue(entry.submenuEntries.allSatisfy(\.isSelectable))
    }

    func testGroupContainingFocusedChildIsSelectable() throws {
        let document = try document(for: """
        group {
            focus cube
            sphere
        }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)
        XCTAssertEqual(entries.map(\.isSelectable), [true, true, false])
    }

    func testDebugOperandDoesNotMakeSiblingsSelectable() throws {
        for operation in ["union", "difference", "intersection", "xor", "stencil"] {
            let document = try document(for: "\(operation) { cube\ndebug sphere }")
            XCTAssertTrue(document.geometry.build { false })
            let entries = flattenedSelectionMenuEntries(for: document)
            XCTAssertEqual(entries.map(\.geometry.type.logDescription), [operation, "sphere"])
            let parent = try XCTUnwrap(document.geometry.children.first)
            let contextEntries = document.selectionMenuEntries(for: [parent] + parent.children)
            XCTAssertEqual(contextEntries.count, 1)
            XCTAssertEqual(contextEntries[0].children.map(\.geometry.type.logDescription), ["sphere"])
            XCTAssertFalse(parent.children[0].isSelectableInSelectionMenu(focus: false))
            XCTAssertTrue(parent.children[1].isSelectableInSelectionMenu(focus: false))
        }
    }

    func testBuiltBooleanOperationsHaveNoSubmenuForConsumedChildren() throws {
        for operation in ["union", "difference", "intersection", "xor", "stencil"] {
            let document = try document(for: "\(operation) { cube\nsphere }")
            XCTAssertTrue(document.geometry.build { false })
            let entry = try XCTUnwrap(document.selectionMenuEntries.first)
            XCTAssertTrue(entry.isSelectable)
            XCTAssertTrue(entry.children.isEmpty, operation)
            let contextEntries = document.selectionMenuEntries(
                for: [entry.geometry] + entry.geometry.children
            )
            XCTAssertEqual(contextEntries.count, 1, operation)
            XCTAssertTrue(contextEntries[0].children.isEmpty, operation)
        }
    }

    func testHiddenShapesAppearAsDisabledLeaves() throws {
        let document = try document(for: """
        group {
            cube
            hide sphere
        }
        hide group { cylinder }
        """)
        let entries = flattenedSelectionMenuEntries(for: document)
        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "cube", "sphere", "group"])
        XCTAssertEqual(entries.map(\.isSelectable), [true, true, false, false])
        XCTAssertTrue(entries[2].children.isEmpty)
        XCTAssertTrue(entries[3].children.isEmpty)
        let context = document.selectionMenuEntries(for: entries.map(\.geometry))
        XCTAssertEqual(context.count, 2)
        XCTAssertFalse(context[0].children[1].isSelectable)
        XCTAssertFalse(context[1].isSelectable)
        XCTAssertTrue(context[1].children.isEmpty)
    }

    func testSelectionMenuDisablesGroupWithOnlyHiddenChildren() throws {
        let document = try document(for: """
        group {
            hide cube
        }
        sphere
        """)
        let entries = flattenedSelectionMenuEntries(for: document)

        XCTAssertEqual(entries.map(\.geometry.type.logDescription), ["group", "sphere"])
        XCTAssertFalse(entries[0].isSelectable)
        XCTAssertTrue(entries[0].children.isEmpty)
        XCTAssertTrue(entries[1].isSelectable)
        XCTAssertEqual(document.selectableGeometries.map(\.type.logDescription), ["sphere"])
    }
}
