//
//  main.swift
//  CLI
//
//  Created by Nick Lockwood on 31/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation

let arguments = CommandLine.arguments
let directory = FileManager.default.currentDirectoryPath

do {
    let cli = try CLI(in: directory, with: arguments)
    try cli.run()
    exit(0)
} catch {
    print(error.localizedDescription)
    exit(-1)
}
