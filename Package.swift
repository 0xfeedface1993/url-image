// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "URLImage",
    platforms: [
        .iOS(.v14),
        .tvOS(.v12),
        .macOS(.v10_15),
        .watchOS(.v4)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "URLImage",
            targets: ["URLImage"]),
        .library(
            name: "URLImageStore",
            targets: ["URLImageStore"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "URLImage",
            dependencies: [ "DownloadManager", "ImageDecoder", "FileIndex", "Model", "Log" ]),
        .target(
            name: "URLImageStore",
            dependencies: [ "URLImage", "FileIndex", "Log" ]),
        .target(
            name: "ImageDecoder",
            path: "Dependencies/Sources/ImageDecoder"),
        .target(
            name: "FileIndex",
            dependencies: [ "PlainDatabase", "Log", "Model" ],
            path: "Dependencies/Sources/FileIndex"),
        .target(
            name: "PlainDatabase",
            path: "Dependencies/Sources/PlainDatabase"),
        .target(
            name: "DownloadManager",
            dependencies: [ "Log" ],
            path: "Dependencies/Sources/DownloadManager"),
        .target(
            name: "Log",
            path: "Dependencies/Sources/Log"),
        .target(
            name: "Model",
            dependencies: [ "ImageDecoder", "DownloadManager" ],
            path: "Dependencies/Sources/Model"),
        .testTarget(
            name: "URLImageTests",
            dependencies: ["URLImage"]),
        .testTarget(
            name: "ImageDecoderTests",
            dependencies: ["ImageDecoder"],
            path: "Dependencies/Tests/ImageDecoderTests",
            resources: [ .copy("Resources/TestImages.json"),
                         .copy("Resources/lenna.jpg"),
                         .copy("Resources/lenna.png"),
                         .copy("Resources/sea_animation.heics"),
                         .copy("Resources/gif-loop-count.gif"),
                         .copy("Resources/quicksort.gif"),
                         .copy("Resources/test.base64")
            ]),
        .testTarget(
            name: "FileIndexTests",
            dependencies: ["FileIndex"],
            path: "Dependencies/Tests/FileIndexTests"),
        .testTarget(
            name: "PlainDatabaseTests",
            dependencies: ["PlainDatabase"],
            path: "Dependencies/Tests/PlainDatabaseTests"),
    ]
)
