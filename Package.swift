// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Atac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AtacCore", targets: ["AtacCore"]),
        .executable(name: "Atac", targets: ["Atac"]),
        .executable(name: "AtacTests", targets: ["AtacTests"])
    ],
    targets: [
        .target(
            name: "AtacCore",
            path: "Sources/AtacCore"
        ),
        .executableTarget(
            name: "Atac",
            dependencies: ["AtacCore"],
            path: "Sources/AtacApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "AtacTests",
            dependencies: ["AtacCore"],
            path: "Sources/AtacTests"
        )
    ]
)
