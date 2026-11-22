// swift-tools-version:5.9
// Sill 앱 — SillCore(엔진 실행 · VM 목록 · 입력 검사, Foundation 만)와 SillApp(SwiftUI 화면, macOS 전용)
import PackageDescription

let package = Package(
    name: "Sill",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sill", targets: ["SillApp"]),
        .library(name: "SillCore", targets: ["SillCore"]),
    ],
    targets: [
        .target(name: "SillCore"),
        .executableTarget(name: "SillApp", dependencies: ["SillCore"]),
        .testTarget(name: "SillCoreTests", dependencies: ["SillCore"]),
    ]
)
