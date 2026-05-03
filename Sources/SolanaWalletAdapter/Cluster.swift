import Foundation

public enum Cluster: String, Sendable, CaseIterable {
    case mainnetBeta = "mainnet-beta"
    case devnet
    case testnet
}
