import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterBackpack
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare

public enum WalletProviderRegistry {
    public static let supportedProviders: [any WalletProvider] = [
        PhantomAdapter(),
        SolflareAdapter(),
        BackpackAdapter(),
    ]

    public static func provider(for id: String) -> (any WalletProvider)? {
        supportedProviders.first { $0.walletId == id }
    }
}
