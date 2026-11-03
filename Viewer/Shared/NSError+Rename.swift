//
//  NSError+Rename.swift
//  ShapeScript Viewer
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import FileProvider
import Foundation

extension NSError {
    var isHandledRenameError: Bool {
        // The document browser presents its own name-validation/conflict UI.
        // Dismissing that UI can also report cancellation.
        if domain == NSCocoaErrorDomain, [
            CocoaError.Code.fileWriteFileExists.rawValue,
            CocoaError.Code.fileWriteInvalidFileName.rawValue,
            CocoaError.Code.userCancelled.rawValue,
        ].contains(code) {
            return true
        }
        if domain == NSFileProviderErrorDomain,
           code == NSFileProviderError.filenameCollision.rawValue
        {
            return true
        }
        return (userInfo[NSUnderlyingErrorKey] as? NSError)?.isHandledRenameError ?? false
    }
}
