// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonoInference",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "MonoInference", targets: ["MonoInference"])],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b6750/llama-b6750-xcframework.zip",
            checksum: "769478a7997c5bc67f5f10c4593e35b6278e4b6b70279f11ddf4f40d6e85a94f"),
        .target(name: "MonoInference", dependencies: ["llama"]),
    ]
)
