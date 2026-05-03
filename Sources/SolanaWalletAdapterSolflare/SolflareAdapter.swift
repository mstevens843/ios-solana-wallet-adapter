import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Solflare-specific iWA v0.1 adapter. See `docs/research/solflare.md`.
public struct SolflareAdapter: WalletProvider {
    public let walletId = "solflare"
    public let universalLinkHost = "solflare.com"
    public let customScheme = "solflare"

    public init() {}

    public func connectURL(request: ConnectRequest) throws -> URL {
        let host = DeeplinkURL.WalletHost(
            universalLinkHost: universalLinkHost,
            customScheme: customScheme
        )
        return try DeeplinkURL.make(
            host: host,
            method: "connect",
            params: [
                ("app_url", request.appURL.absoluteString),
                ("dapp_encryption_public_key", request.dappEncryptionPublicKey),
                ("redirect_link", request.redirectLink.absoluteString),
                ("cluster", request.cluster.rawValue),
            ]
        )
    }
}
