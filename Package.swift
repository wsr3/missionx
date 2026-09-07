// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MissionX",
    platforms: [.macOS(.v14)],
    targets: [
        // The app itself.
        .executableTarget(
            name: "MissionX",
            path: "Sources/MissionX",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Diagnostic tool: dumps the Dock's accessibility tree and the window
        // list while Mission Control is open. Use it if a macOS update changes
        // the tree and MissionX stops finding thumbnails.
        .executableTarget(
            name: "AXProbe",
            path: "Sources/AXProbe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Diagnostic tool: shows bars at several window-server levels so you
        // can check which ones still draw on top of Mission Control.
        .executableTarget(
            name: "OverlayProbe",
            path: "Sources/OverlayProbe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
