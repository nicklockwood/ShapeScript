//
//  SourceViewController.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 19/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ShapeScript
import UIKit

class SourceViewController: UIViewController {
    @IBOutlet private var textView: TokenView!

    var document: Document? {
        willSet { document?.undoManager = nil }
        didSet { didSetDocument() }
    }

    override var undoManager: UndoManager? {
        document?.undoManager
    }

    func didSetDocument() {
        title = document?.fileURL.lastPathComponent
        if let textView = textView {
            textView.text = document?.sourceString ?? ""
            textView.isEditable = document?.isEditable ?? false
            document?.undoManager = textView.undoManager
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.showLineNumbers = true
        textView.wrapLines = false
        textView.disableDoubleSpacePeriodShortcut = true
        textView.delegate = self
        didSetDocument()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .action,
            primaryAction: UIAction { [weak self] _ in
                guard let self = self, let document = self.document else {
                    return
                }
                let sheet = UIActivityViewController(
                    activityItems: [
                        UISimpleTextPrintFormatter(text: document.sourceString ?? ""),
                        document.fileURL,
                    ],
                    applicationActivities: nil
                )
                sheet.popoverPresentationController?
                    .barButtonItem = self.navigationItem.rightBarButtonItem
                self.present(sheet, animated: true)
            }
        )
    }
}

extension TokenView.TokenType {
    static let `default` = Self(rawValue: "default")
    static let `operator` = Self(rawValue: "operator")
    static let identifier = Self(rawValue: "identifier")
    static let keyword = Self(rawValue: "keyword")
    static let string = Self(rawValue: "string")
    static let number = Self(rawValue: "number")
    static let color = Self(rawValue: "color")
    static let member = Self(rawValue: "member")
    static let stdlib = Self(rawValue: "stdlib")
}

extension TokenType {
    var tokenViewType: TokenView.TokenType {
        switch self {
        case .dot, .prefix, .infix, .lbrace, .rbrace, .lparen, .rparen, .call, .lbracket, .rbracket, .subscript:
            return .operator
        case .identifier:
            return .identifier
        case .keyword:
            return .keyword
        case .hexColor:
            return .color
        case .number:
            return .number
        case .string:
            return .string
        case .linebreak, .eof:
            return .default
        }
    }
}

extension Token {
    var tokenViewToken: TokenView.Token {
        .init(
            type: type.tokenViewType,
            range: range
        )
    }
}

extension SourceViewController: TokenViewDelegate {
    func tokens(for input: String) -> [TokenView.Token] {
        var stack = [Set<String>()]
        var isSwitch = [false]
        var lastKeyword: String?
        var lastToken: ShapeScript.Token?
        return (try? tokenize(input).flatMap { token -> [TokenView.Token] in
            defer { lastToken = token }
            var viewToken = token.tokenViewToken
            switch token.type {
            case .lbrace:
                stack.append(stack.last!)
                isSwitch.append(lastKeyword == "switch")
            case .rbrace where stack.count > 1:
                stack.removeLast()
                isSwitch.removeLast()
            case .linebreak, .eof:
                lastKeyword = nil
            case let .keyword(name):
                lastKeyword = name.rawValue
            case let .identifier(name):
                if lastKeyword == "option",
                   case .identifier("option")? = lastToken?.type
                {
                    stack[stack.count - 1].insert(name)
                    lastKeyword = nil
                    break
                }
                if isSwitch.last == true, name == "case" {
                    viewToken.type = .keyword
                    break
                }
                if case .keyword(.define)? = lastToken?.type {
                    stack[stack.count - 1].insert(name)
                    lastKeyword = nil
                    break
                } else if case .dot = lastToken?.type {
                    viewToken.type = .member
                    break
                }
                if stack.last!.contains(name) {
                    break
                }
                switch name {
                case "in", "to", "step", "option", "not", "true", "false", "switch":
                    // contextual keywords
                    viewToken.type = .keyword
                    lastKeyword = name
                case _ where ShapeScript.stdlibSymbols.contains(name):
                    viewToken.type = .stdlib
                default:
                    break
                }
            default:
                break
            }
            let lastBound = lastToken?.range.upperBound ?? "".startIndex
            let lastRange = lastBound ..< token.range.lowerBound
            if !lastRange.isEmpty, input[lastRange].contains("/") {
                return [.init(type: .default, range: lastRange), viewToken]
            }
            return [viewToken]
        }) ?? []
    }

    func attributes(for tokenType: TokenView.TokenType) -> [NSAttributedString.Key: Any] {
        switch tokenType {
        case .keyword:
            return [.foregroundColor: UIColor.systemPurple]
        case .number:
            return [.foregroundColor: UIColor.orange]
        case .string, .color:
            return [.foregroundColor: UIColor.systemRed]
        case .stdlib, .member:
            return [.foregroundColor: UIColor {
                $0.userInterfaceStyle == .dark ? .systemTeal : .systemIndigo
            }]
        case .default:
            return [.foregroundColor: UIColor.systemGray]
        case .identifier, .operator, _:
            return [:]
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        document?.sourceString = textView.text
        document?.scheduleAutosave()
        document?.fileMonitor?.markUpdated()
        if undoManager?.isUndoing ?? false {
            document?.updateChangeCount(.undone)
        } else if undoManager?.isRedoing ?? false {
            document?.updateChangeCount(.redone)
        } else {
            document?.updateChangeCount(.done)
        }
    }
}

extension SourceViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let navigationBar = navigationController?.navigationBar
        let underMenu = scrollView.contentOffset.y > -view.safeAreaInsets.top
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            if underMenu {
                appearance.configureWithDefaultBackground()
            } else {
                appearance.configureWithTransparentBackground()
            }
            navigationBar?.scrollEdgeAppearance = appearance
        } else if underMenu {
            navigationBar?.standardAppearance.configureWithDefaultBackground()
        } else {
            navigationBar?.standardAppearance.configureWithTransparentBackground()
        }
    }
}
