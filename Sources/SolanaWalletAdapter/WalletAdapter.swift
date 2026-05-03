import Foundation

/// Thin entry point that holds a chosen `WalletProvider`. Phase 2 will grow
/// this into a stateful object that owns the ephemeral keypair, the active
/// session, and the URL-callback continuation.
public final class WalletAdapter {
    public let provider: WalletProvider

    public init(provider: WalletProvider) {
        self.provider = provider
    }
}
