// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EncoBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "EncoBar", targets: ["EncoBar"]),
               .executable(name: "EncoBarUninstaller", targets: ["EncoUninstaller"])],
    targets: [
        .target(name: "EncoCore"),
        .executableTarget(name: "EncoBar", dependencies: ["EncoCore"],
                          linkerSettings: [.linkedFramework("IOBluetooth")]),
        .executableTarget(name: "EncoUninstaller", dependencies: ["EncoCore"],
                          linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "EncoCoreChecks", dependencies: ["EncoCore"], path: "Tests/EncoCoreChecks")
    ]
)
