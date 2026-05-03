// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BiliCastHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BiliCast", targets: ["BiliCastApp"]),
        .library(name: "BiliCastCore", targets: ["BiliCastCore"]),
        .library(name: "BiliCastHTTP", targets: ["BiliCastHTTP"]),
        .library(name: "BiliCastDLNA", targets: ["BiliCastDLNA"]),
    ],
    targets: [
        .target(name: "BiliCastCore", path: "Sources/BiliCastCore"),
        .target(
            name: "BiliCastHTTP",
            dependencies: ["BiliCastCore"],
            path: "Sources/BiliCastHTTP"
        ),
        .target(
            name: "BiliCastDLNA",
            dependencies: ["BiliCastCore"],
            path: "Sources/BiliCastDLNA"
        ),
        .executableTarget(
            name: "BiliCastApp",
            dependencies: ["BiliCastCore", "BiliCastHTTP", "BiliCastDLNA"],
            path: "Sources/BiliCastApp"
        ),
    ]
)
