//
//  Document+EvaluationDelegate.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 10/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import SCADLib
import SceneKit
import ShapeScript

extension Document: EvaluationDelegate {
    func resolveURL(for path: String) -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: fileURL)
        linkedResources.insert(url)
        if let resolvedURL = resolveBookMark(for: url) {
            if resolvedURL.path != url.path {
                // File was moved, so return the original url (which will throw a file-not-found error)
                // TODO: we could handle this more gracefully by reporting that the file was moved
                return url
            }
            return resolvedURL
        } else {
            bookmarkURL(url)
        }
        return url
    }

    func importGeometry(for url: URL) throws -> Geometry? {
        switch url.pathExtension.lowercased() {
        case "scad":
            do {
                let source = try String(contentsOf: url)
                let scadProgram = try SCADLib.parse(source)
                let program = ShapeScript.Program(scadProgram)
                return try Geometry(
                    type: .group,
                    name: nil,
                    transform: .identity,
                    material: .default,
                    smoothing: nil,
                    wrapMode: nil,
                    children: evaluate(
                        program,
                        delegate: self,
                        baseURL: url
                    ).children,
                    sourceLocation: nil
                )
            } catch let error as SCADLib.LexerError {
                let type: ShapeScript.LexerErrorType
                switch error.type {
                case let .invalidNumber(string):
                    type = .invalidNumber(string)
                case let .unexpectedToken(string):
                    type = .unexpectedToken(string)
                case .unterminatedString:
                    type = .unterminatedString
                case let .invalidEscapeSequence(string):
                    type = .invalidEscapeSequence(string)
                }
                throw ProgramError.lexerError(.init(type, at: error.range))
            } catch let error as SCADLib.ParserError {
                throw ProgramError.parserError(.init(.custom(
                    error.message,
                    hint: error.hint,
                    at: error.range
                )))
            } catch let error as RuntimeError {
                throw ProgramError.runtimeError(error)
            } catch {
                throw error
            }
        default:
            return nil
        }
    }

    func debugLog(_ values: [AnyHashable]) {
        let line: String
        if values.count == 1 {
            line = String(logDescriptionFor: values[0] as Any)
        } else {
            var spaceNeeded = false
            line = values.compactMap {
                switch $0 {
                case let string as String:
                    spaceNeeded = false
                    return string
                case let value:
                    let string = String(nestedLogDescriptionFor: value as Any)
                    defer { spaceNeeded = true }
                    return spaceNeeded ? " \(string)" : string
                }
            }.joined()
        }

        Swift.print(line)
        DispatchQueue.main.async { [weak self] in
            if let viewController = self?.viewController {
                viewController.showConsole = true
                viewController.appendLog(line + "\n")
            }
        }
    }
}
