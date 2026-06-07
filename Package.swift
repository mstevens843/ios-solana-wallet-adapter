// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SolanaWalletAdapter",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SolanaWalletAdapter",
            targets: ["SolanaWalletAdapter"]
        ),
        .library(
            name: "SolanaWalletAdapterPhantom",
            targets: ["SolanaWalletAdapterPhantom"]
        ),
        .library(
            name: "SolanaWalletAdapterSolflare",
            targets: ["SolanaWalletAdapterSolflare"]
        ),
        .library(
            name: "SolanaWalletAdapterBackpack",
            targets: ["SolanaWalletAdapterBackpack"]
        ),
        .library(
            name: "SolanaWalletAdapterJupiter",
            targets: ["SolanaWalletAdapterJupiter"]
        ),
        .library(
            name: "SolanaWalletAdapterJupiterHandler",
            targets: ["SolanaWalletAdapterJupiterHandler"]
        ),
        .library(
            name: "SolanaWalletAdapterWalletConnect",
            targets: ["SolanaWalletAdapterWalletConnect"]
        ),
        .library(
            name: "SolanaWalletAdapterReturnUX",
            targets: ["SolanaWalletAdapterReturnUX"]
        ),
        .library(
            name: "SolanaWalletAdapterUI",
            targets: ["SolanaWalletAdapterUI"]
        ),
        .library(
            name: "SolanaWalletAdapterPicker",
            targets: ["SolanaWalletAdapterPicker"]
        ),
    ],
    targets: [
        .target(
            name: "SolanaWalletAdapter",
            dependencies: ["SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterCore"
        ),
        .target(
            name: "SolanaWalletAdapterPhantom",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterSolflare",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterBackpack",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterJupiter",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterJupiterHandler",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterWalletConnect",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterReturnUX"
        ),
        .target(
            name: "SolanaWalletAdapterUI",
            dependencies: [
                "SolanaWalletAdapter",
                "SolanaWalletAdapterCore",
                "SolanaWalletAdapterPhantom",
                "SolanaWalletAdapterSolflare",
                "SolanaWalletAdapterBackpack",
                "SolanaWalletAdapterJupiter",
            ]
        ),
        .target(
            name: "SolanaWalletAdapterPicker",
            dependencies: [
                "SolanaWalletAdapter",
                "SolanaWalletAdapterCore",
                "SolanaWalletAdapterUI",
                "SolanaWalletAdapterPhantom",
                "SolanaWalletAdapterSolflare",
                "SolanaWalletAdapterBackpack",
                "SolanaWalletAdapterWalletConnect",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SolanaWalletAdapterTests",
            dependencies: [
                "SolanaWalletAdapter",
                "SolanaWalletAdapterCore",
                "SolanaWalletAdapterPhantom",
                "SolanaWalletAdapterSolflare",
                "SolanaWalletAdapterBackpack",
                "SolanaWalletAdapterJupiter",
                "SolanaWalletAdapterJupiterHandler",
                "SolanaWalletAdapterWalletConnect",
                "SolanaWalletAdapterUI",
                "SolanaWalletAdapterPicker",
            ]
        ),
    ]
)
