import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Phantom-specific iWA v0.1 adapter.
///
/// Phase 1: builds the `connect` URL per the protocol shape documented at
/// `docs/research/phantom.md`. Subsequent methods (signMessage, signTransaction,
/// signAndSendTransaction) ship in Phase 2 once the NaCl box layer is wired.
public struct PhantomAdapter: WalletProvider {
    public let walletId = "phantom"
    public let universalLinkHost = "phantom.app"
    public let customScheme = "phantom"

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
