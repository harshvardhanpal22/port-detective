// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortDetective",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PortDetective",
            path: "Sources/PortDetective",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
