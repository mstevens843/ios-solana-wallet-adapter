import Foundation

/// A wallet provider implements the iWA v0.1 protocol for one specific wallet
/// (Phantom, Solflare, Backpack, ...). Adapters are constructed by the consumer
/// and used either directly or through `WalletAdapter`.
public protocol WalletProvider: Sendable {
    /// Stable identifier for the wallet, e.g. "phantom", "solflare", "backpack".
    var walletId: String { get }

    /// Universal-link host this provider targets, e.g. "phantom.app".
    var universalLinkHost: String { get }

    /// Custom URL scheme fallback, e.g. "phantom".
    var customScheme: String { get }

    /// Static wallet metadata and method support exposed by client capability
    /// introspection.
    var capabilities: WalletProviderCapabilities { get }

    /// Build the connect URL for this wallet given the app's ephemeral
    /// encryption keypair and the redirect destination the wallet should
    /// bounce the user back to.
    func connectURL(request: ConnectRequest) throws -> URL
}

/// Parameters required to build a connect deeplink.
public struct ConnectRequest: Sendable {
    /// Base58-encoded X25519 public key for the app's ephemeral encryption keypair.
    public let dappEncryptionPublicKey: String
    /// Where the wallet should redirect the user after the user approves.
    public let redirectLink: URL
    /// URL providing app metadata (title, icon). Wallets render this in the approval screen.
    public let appURL: URL
    /// Cluster the app intends to use. Default: mainnet-beta.
    public let cluster: Cluster

    public init(
        dappEncryptionPublicKey: String,
        redirectLink: URL,
        appURL: URL,
        cluster: Cluster = .mainnetBeta
    ) {
        self.dappEncryptionPublicKey = dappEncryptionPublicKey
        self.redirectLink = redirectLink
        self.appURL = appURL
        self.cluster = cluster
    }
}
