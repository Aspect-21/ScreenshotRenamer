// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotRenamer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotRenamer",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Info.plist"])
            ]
        )
    ]
)

