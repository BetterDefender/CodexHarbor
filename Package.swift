// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodexHarbor", platforms: [.macOS(.v13)], products: [.executable(name: "CodexHarbor", targets: ["CodexHarbor"])], targets: [.executableTarget(name: "CodexHarbor")])
