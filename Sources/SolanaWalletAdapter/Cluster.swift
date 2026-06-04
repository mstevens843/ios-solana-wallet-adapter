import Foundation

public enum Cluster: String, Sendable, CaseIterable, Codable {
    case mainnetBeta = "mainnet-beta"
    case devnet
    case testnet
}

public extension Cluster {
    init?(environmentValue: String) {
        switch environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mainnet", "mainnet-beta", "solana:mainnet", "solana:mainnet-beta":
            self = .mainnetBeta
        case "devnet", "solana:devnet":
            self = .devnet
        case "testnet", "solana:testnet":
            self = .testnet
        default:
            return nil
        }
    }
}
