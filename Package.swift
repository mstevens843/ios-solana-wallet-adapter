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
            name: "SolanaWalletAdapterWalletConnect",
            targets: ["SolanaWalletAdapterWalletConnect"]
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
            name: "SolanaWalletAdapterWalletConnect",
            dependencies: ["SolanaWalletAdapter", "SolanaWalletAdapterCore"]
        ),
        .target(
            name: "SolanaWalletAdapterUI",
            dependencies: [
                "SolanaWalletAdapter",
                "SolanaWalletAdapterCore",
                "SolanaWalletAdapterPhantom",
                "SolanaWalletAdapterSolflare",
                "SolanaWalletAdapterBackpack",
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
                "SolanaWalletAdapterWalletConnect",
                "SolanaWalletAdapterUI",
                "SolanaWalletAdapterPicker",
            ]
        ),
    ]
)
