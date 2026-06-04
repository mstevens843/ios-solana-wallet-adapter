import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Backpack-specific iWA v0.1 adapter. See `docs/research/backpack.md`.
public struct BackpackAdapter: WalletProvider {
    public let walletId = "backpack"
    public let universalLinkHost = "backpack.app"
    public let customScheme = "backpack"

    public init() {}

    public var capabilities: WalletProviderCapabilities {
        WalletProviderCapabilities(
            walletId: walletId,
            displayName: "Backpack",
            universalLinkHost: universalLinkHost,
            customScheme: customScheme,
            methods: WalletMethod.nativeDeeplinkProtocolMethods.map { .init(method: $0) }
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
