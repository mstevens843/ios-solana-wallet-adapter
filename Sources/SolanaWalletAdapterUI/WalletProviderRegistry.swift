import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterBackpack
import SolanaWalletAdapterJupiter
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare

public enum WalletProviderRegistry {
    /// Verified, production-ready native providers (real-device confirmed).
    public static let supportedProviders: [any WalletProvider] = [
        PhantomAdapter(),
        SolflareAdapter(),
        BackpackAdapter(),
    ]

    /// Opt-in providers not yet real-device verified. Jupiter targets the jWA
    /// profile (`jwa:requires-handler`): it works against any jWA-conformant
    /// wallet, but real Jupiter native support is pending on-device confirmation,
    /// so it is kept out of `supportedProviders` while still being resolvable so
    /// picker selection doesn't dead-end. See `docs/research/jupiter.md`.
    public static let previewProviders: [any WalletProvider] = [
        JupiterAdapter(),
    ]

    /// All resolvable providers (verified + preview).
    public static var allProviders: [any WalletProvider] { supportedProviders + previewProviders }

    public static func provider(for id: String) -> (any WalletProvider)? {
        allProviders.first { $0.walletId == id }
    }
}
