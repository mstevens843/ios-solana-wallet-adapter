import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Phantom-specific iWA v0.1 adapter.
///
public struct PhantomAdapter: WalletProvider {
    public let walletId = "phantom"
    public let universalLinkHost = "phantom.app"
    public let customScheme = "phantom"

    public init() {}

    public var capabilities: WalletProviderCapabilities {
        WalletProviderCapabilities(
            walletId: walletId,
            displayName: "Phantom",
            universalLinkHost: universalLinkHost,
            customScheme: customScheme,
            methods: [
                .init(method: .connect),
                .init(method: .disconnect),
                .init(method: .signMessage),
                .init(method: .signTransaction),
                .init(method: .signAllTransactions),
                .init(
                    method: .signAndSendTransaction,
                    isDeprecated: true,
                    note: "Phantom marks signAndSendTransaction as deprecated; prefer signTransaction followed by app-side send."
                ),
            ]
        )
    }

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
