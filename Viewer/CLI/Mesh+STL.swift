//
//  Geometry+Export.swift
//  CLI
//
//  Created by Nick Lockwood on 14/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

extension Mesh {
    func stlString(name: String) -> String {
        """
        solid \(name)
        \(triangulate().polygons.map { $0.stlString }.joined(separator: "\n"))
        endsolid \(name)
        """
    }
}

private extension Polygon {
    var stlString: String {
        """
        facet normal \(plane.normal.logDescription)
            outer loop
                vertex \(vertices[0].position.logDescription)
                vertex \(vertices[1].position.logDescription)
                vertex \(vertices[2].position.logDescription)
            endloop
        endfacet
        """
    }
}
