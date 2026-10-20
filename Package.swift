// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DiscoSeguro", platforms: [.macOS(.v14)], products: [.library(name: "DiscoCore", targets: ["DiscoCore"]), .executable(name: "DiscoSeguro", targets: ["DiscoSeguro"])], targets: [.target(name: "DiscoCore"), .executableTarget(name: "DiscoSeguro", dependencies: ["DiscoCore"]), .testTarget(name: "DiscoCoreTests", dependencies: ["DiscoCore"])])
