// swift-tools-version: 5.9
import PackageDescription
import Foundation
let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().path
let package = Package(name: "ScrcpyIOS", platforms: [.macOS(.v13), .iOS(.v16)], products: [
    .library(name: "ScrcpyCore", targets: ["ScrcpyCore"]),
    .executable(name: "scrcpy-probe", targets: ["ScrcpyProbe"])
], targets: [
    .target(name:"AdbCrypto", path:"Sources/AdbCrypto", publicHeadersPath:"include", cSettings:[.unsafeFlags(["-I\(root)/build/boringssl/include"])], linkerSettings:[.unsafeFlags(["-L\(root)/build/boringssl/macosx/lib","-lssl","-lcrypto","-lc++"])]),
    .target(name: "ScrcpyCore", dependencies:["AdbCrypto"], path: "Sources/Core"),
    .executableTarget(name: "ScrcpyProbe", dependencies: ["ScrcpyCore"], path: "Sources/Probe"),
    .testTarget(name: "CoreTests", dependencies: ["ScrcpyCore"], path: "Tests/CoreTests")
], cxxLanguageStandard: .cxx17)
