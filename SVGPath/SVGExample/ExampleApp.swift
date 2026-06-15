//
//  ExampleApp.swift
//  SVGExample
//
//  Created by Nick Lockwood on 23/12/2025.
//  Copyright © 2025 Nick Lockwood. All rights reserved.
//

import SVGPath
import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Heart()
            .fill(Color.red)
            .shadow(radius: 5)
            .scaledToFit()
            .padding()
    }
}

struct Heart: Shape {
    func path(in rect: CGRect) -> Path {
        try! Path(svgPath: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9 C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """, in: rect)
    }
}
