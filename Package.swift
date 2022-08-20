// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChainTester",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ChainTester",
            targets: ["ChainTester"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "Thrift",
                 url: "/Users/newworld/dev/swift/Thrift2",
                 .branch("master")),
        .package(name: "PlayingCard",
                 url: "https://github.com/apple/example-package-playingcard.git",
                 .branch("main")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ChainTester",
            dependencies: [
                .byName(name: "Thrift"),
                .byName(name: "PlayingCard"),
            ]),
        .testTarget(
            name: "ChainTesterTests",
            dependencies: ["ChainTester"]),
    ]
)
