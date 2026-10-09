// swift-tools-version:6.2
import PackageDescription

// Build with ./scripts/build-app.sh — it uses xcodebuild, because SwiftPM on the
// command line can't compile MLX's Metal kernels.
let package = Package(
    name: "Assist",
    platforms: [.macOS("26.0")],
    dependencies: [
        // On-device LLM inference (MLX, Metal + M5 Neural Accelerators).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        // Tokenizers for the MLX models.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        // Parakeet streaming speech recognition on the Neural Engine.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .executableTarget(
            name: "Assist",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Assist",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
