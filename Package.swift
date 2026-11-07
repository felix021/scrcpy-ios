// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ScrcpyIOS", platforms: [.macOS(.v13), .iOS(.v16)], products: [
    .library(name: "ScrcpyCore", targets: ["ScrcpyCore"]),
    .executable(name: "scrcpy-probe", targets: ["ScrcpyProbe"])
], targets: [
    .target(name: "ScrcpyCore", path: "Sources/Core"),
    .executableTarget(name: "ScrcpyProbe", dependencies: ["ScrcpyCore"], path: "Sources/Probe"),
    .testTarget(name: "CoreTests", dependencies: ["ScrcpyCore"], path: "Tests/CoreTests")
])
