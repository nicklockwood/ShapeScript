//
//  SCADLibTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 06/01/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import SCADLib
@testable import ShapeScript
import XCTest

private func evaluateSCAD(_ scad: String) throws -> [Value] {
    let program = try SCADLib.parse(scad)
    let context = EvaluationContext(source: scad, delegate: nil)
    try ShapeScript.Program(program).evaluate(in: context)
    return context.children
}

private func evaluateShape(_ shape: String) throws -> [Value] {
    let program = try ShapeScript.parse(shape)
    let context = EvaluationContext(source: shape, delegate: nil)
    try program.evaluate(in: context)
    return context.children
}

class SCADLibTests: XCTestCase {
    // MARK: 3D Shapes

    func testSphere() {
        XCTAssertEqual(
            try evaluateSCAD("sphere();"),
            try evaluateShape("sphere { size 2 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("sphere(5);"),
            try evaluateShape("sphere { size 10 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("sphere(r=5);"),
            try evaluateShape("sphere { size 10 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("sphere(2,d=5);"),
            try evaluateShape("sphere { size 5 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("sphere(d=5,r=3);"),
            try evaluateShape("sphere { size 5 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("sphere($fn=10,d=1);"),
            try evaluateShape("sphere { detail 10 }")
        )
    }

    func testCube() {
        XCTAssertEqual(
            try evaluateSCAD("cube();"),
            try evaluateShape("cube { position size / 2 }")
        )
        XCTAssertEqual(
            try evaluateSCAD("cube(1,true);"),
            try evaluateShape("cube")
        )
        XCTAssertEqual(
            try evaluateSCAD("cube([1,2,3]);"),
            try evaluateShape("""
            cube {
                size 1 2 3
                position size / 2
            }
            """)
        )
        XCTAssertEqual(
            try evaluateSCAD("cube(center=true,size=[1,2,3]);"),
            try evaluateShape("cube { size 1 2 3 }")
        )
    }

    // MARK: Builders

    func testExtrude() {
        XCTAssertEqual(
            try evaluateSCAD("""
            linear_extrude(height = 60, twist = 90, slices = 60) {
                square(20, center = true);
            }
            """),
            try evaluateShape("""
            extrude {
                size 1 1 60
                position 0 0 30
                twist 0.5
                detail 60 * 4
                square { size 20 }
            }
            """)
        )
    }

    // MARK: Colors

    func testVectorColor() {
        XCTAssertEqual(
            try evaluateSCAD("color([1,0,0]) cube(1,true);"),
            try evaluateShape("group { color 1 0 0\ncube }")
        )
        XCTAssertEqual(
            try evaluateSCAD("color([1,0,0,0.5]) cube(1,true);"),
            try evaluateShape("group { color 1 0 0 0.5\ncube }")
        )
        XCTAssertEqual(
            try evaluateSCAD("color(alpha=0.5,c=[1,0,0]) cube(1,true);"),
            try evaluateShape("group { color 1 0 0 0.5\ncube }")
        )
    }

    func testHexColor() {
        XCTAssertEqual(
            try evaluateSCAD("color(\"#00f\") cube(1,true);"),
            try evaluateShape("group { color 0 0 1\ncube }")
        )
        XCTAssertEqual(
            try evaluateSCAD("color(\"#00f\",0.5) cube(1,true);"),
            try evaluateShape("group { color 0 0 1 0.5\ncube }")
        )
    }

    // MARK: Misc

    func testNameCollision() {
        XCTAssertEqual(
            try evaluateSCAD("""
            size = 10;
            rotation = 17;
            group() {
                rotate([rotation, 0, 0])
                    cube(size);
                rotate([rotation, 0, 0])
                    translate([0, 0, size])
                    cube([2, 3, 4]);
            }
            """),
            try evaluateShape("""
            define size_ 10
            define rotation_ 17
            group {
                group {
                    rotate 0 0 rotation_ / -180
                    cube {
                        size size_
                        position size / 2
                    }
                }
                group {
                    rotate 0 0 rotation_ / -180
                    translate 0 0 size_
                    cube {
                        size 2 3 4
                        position size / 2
                    }
                }
            }
            """)
        )
    }

    func testModule() {
        XCTAssertEqual(
            try evaluateSCAD("""
            module dodecahedron(height) {
                scale([height,height,height]) {
                    intersection(){
                        cube([2,2,1], center=true);
                        intersection_for(i=[0:4]) {
                            rotate([0,0,72*i])
                                rotate([116.565,0,0])
                                cube([2,2,1], center=true);
                        }
                    }
                }
            }
            dodecahedron(2);
            """),
            try evaluateShape("""
            define dodecahedron {
                option height 1
                group {
                    scale height
                    intersection {
                        cube { size 2 2 1 }
                        for i in 0 to 4 {
                            group {
                                rotate 72*i/-180
                                group {
                                    rotate 0 0 116.565/-180
                                    cube { size 2 2 1 }
                                }
                            }
                        }
                    }
                }
            }
            dodecahedron { height 2 }
            """)
        )
    }

    func testCSGInsideBuilder() {
        XCTAssertEqual(
            try evaluateSCAD("""
            linear_extrude(height = 60, twist = 90, slices = 60) {
                difference() {
                    square(20, center = true);
                    square(18, center = true);
                }
            }
            """),
            try evaluateShape("""
            extrude {
                size 1 1 60
                twist 0.5
                detail 60 * 4
                difference {
                    square { size 20 }
                    square { size 18 }
                }
            }
            """)
        )
    }
}
