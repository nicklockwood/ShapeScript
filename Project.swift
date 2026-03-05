// swiftformat:disable all
import ProjectDescription

let marketingVersion = "1.9.3"
let currentProjectVersion = "1"

let project = Project(
    name: "ShapeScript",
    options: .options(
        defaultKnownRegions: ["en", "Base"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        // MARK: - ShapeScript Library

        .target(
            name: "ShapeScript",
            destinations: [.mac, .iPhone, .iPad],
            product: .staticFramework,
            bundleId: "com.charcoaldesign.ShapeScript",
            deploymentTargets: .multiplatform(iOS: "14.0", macOS: "10.15"),
            sources: ["ShapeScript/**/*.swift"],
            scripts: [
                .post(
                    script: #"""
                    export PATH="$PATH:$HOME/.mint/bin:/opt/homebrew/bin"
                    if which swiftformat >/dev/null; then
                      swiftformat . --lint --lenient
                    else
                      echo "warning: SwiftFormat not installed, download from https://github.com/nicklockwood/SwiftFormat"
                    fi
                    """#,
                    name: "Lint Code"
                ),
            ],
            dependencies: [
                .external(name: "Euclid"),
                .external(name: "LRUCache"),
                .external(name: "SVGPath"),
            ]
        ),

        // MARK: - CLI Tool

        .target(
            name: "ShapeScriptCLI",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "com.charcoaldesign.shapescript-cli",
            deploymentTargets: .macOS("10.15"),
            sources: ["Viewer/CLI/**/*.swift"],
            dependencies: [
                .target(name: "ShapeScript"),
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "shapescript",
                    "PRODUCT_MODULE_NAME": "ShapeScriptCLI",
                ]
            )
        ),

        // MARK: - Mac Viewer

        .target(
            name: "ViewerMac",
            destinations: [.mac],
            product: .app,
            bundleId: "com.charcoaldesign.ShapeScriptViewer",
            deploymentTargets: .macOS("10.15"),
            infoPlist: .file(path: "Viewer/Mac/Info.plist"),
            sources: [
                "Viewer/Mac/**/*.swift",
                "Viewer/Shared/**/*.swift",
            ],
            resources: [
                "Viewer/Shared/Assets.xcassets",
                "Viewer/Shared/AppIcon.icon",
                "Viewer/Shared/Untitled.shape",
                "Viewer/Shared/Licenses.rtf",
                "Viewer/Mac/Base.lproj/**",
                "Viewer/Mac/Welcome.rtf",
                "Viewer/Mac/WhatsNew.rtf",
                "Examples/**",
            ],
            entitlements: .file(path: "Viewer/Mac/Viewer.entitlements"),
            scripts: [
                .post(
                    script: #"""
                    chflags -R nouchg "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/Examples/"
                    exit 0
                    """#,
                    name: "Unlock Examples"
                ),
            ],
            dependencies: [
                .target(name: "ShapeScript"),
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "ShapeScript Viewer",
                    "PRODUCT_MODULE_NAME": "Viewer",
                    "MARKETING_VERSION": .init(stringLiteral: marketingVersion),
                    "CURRENT_PROJECT_VERSION": .init(stringLiteral: currentProjectVersion),
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                ]
            )
        ),

        // MARK: - iOS Viewer

        .target(
            name: "VieweriOS",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.charcoaldesign.ShapeScriptViewer",
            deploymentTargets: .iOS("14.0"),
            infoPlist: .file(path: "Viewer/iOS/Info.plist"),
            sources: [
                "Viewer/iOS/**/*.swift",
                "Viewer/Shared/**/*.swift",
            ],
            resources: [
                "Viewer/Shared/Assets.xcassets",
                "Viewer/Shared/AppIcon.icon",
                "Viewer/Shared/Untitled.shape",
                "Viewer/Shared/Licenses.rtf",
                "Viewer/iOS/Base.lproj/**",
                "Viewer/iOS/WhatsNew.rtf",
                "Examples/**",
            ],
            dependencies: [
                .target(name: "ShapeScript"),
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "ShapeScript",
                    "PRODUCT_MODULE_NAME": "Viewer",
                    "MARKETING_VERSION": .init(stringLiteral: marketingVersion),
                    "CURRENT_PROJECT_VERSION": .init(stringLiteral: currentProjectVersion),
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "TARGETED_DEVICE_FAMILY": "1,2,3,7",
                    "DEVELOPMENT_TEAM": "CX9A4TZM67",
                ]
            )
        ),

        // MARK: - Tests

        .target(
            name: "ShapeScriptTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.charcoaldesign.ShapeScriptTests",
            deploymentTargets: .macOS("10.15"),
            sources: ["ShapeScriptTests/**/*.swift"],
            resources: [
                "ShapeScriptTests/TestShapes/**",
                "ShapeScriptTests/Stars1.jpg",
                "ShapeScriptTests/EdgeOfTheGalaxyRegular-OVEa6.otf",
            ],
            scripts: [
                .pre(
                    script: #"""
                    export PATH="$PATH:$HOME/.mint/bin:/opt/homebrew/bin"
                    if which swiftformat >/dev/null; then
                      swiftformat .
                    else
                      echo "warning: SwiftFormat not installed, download from https://github.com/nicklockwood/SwiftFormat"
                    fi
                    """#,
                    name: "Format Code"
                ),
            ],
            dependencies: [
                .target(name: "ShapeScript"),
            ]
        ),
    ]
)
