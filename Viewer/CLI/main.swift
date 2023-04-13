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
guard let cli = CLI(in: directory, with: arguments) else {
    exit(0)
}
exit(cli.run())
