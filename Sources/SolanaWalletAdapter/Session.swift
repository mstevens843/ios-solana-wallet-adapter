import Foundation

/// State established after a successful `connect`. Echoed on every subsequent
/// signing call. Wallets may invalidate sessions; adapters should re-`connect`
/// on `WalletAdapterError.invalidSession`.
public struct Session: Sendable, Equatable {
    /// Wallet's encryption public key, returned in the connect response and used
    /// alongside the app's secret key to derive the shared secret for NaCl box.
    public let walletEncryptionPublicKey: Data
    /// Opaque session token returned by the wallet. Carried as a query param on
    /// every subsequent request.
    public let token: String
    /// User's Solana public key (base58).
    public let userPublicKey: String

    public init(walletEncryptionPublicKey: Data, token: String, userPublicKey: String) {
        self.walletEncryptionPublicKey = walletEncryptionPublicKey
        self.token = token
        self.userPublicKey = userPublicKey
    }
}
