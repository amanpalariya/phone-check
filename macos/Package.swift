// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PhoneCheck", platforms: [.macOS(.v14)],
    products: [.executable(name: "PhoneCheck", targets: ["PhoneCheck"])],
    targets: [
        .target(name: "PhoneCheckCore"),
        .executableTarget(name: "PhoneCheck", dependencies: ["PhoneCheckCore"]),
        .executableTarget(name: "PhoneCheckChecks", dependencies: ["PhoneCheckCore"], path: "Tests/PhoneCheckCoreTests")
    ]
)
