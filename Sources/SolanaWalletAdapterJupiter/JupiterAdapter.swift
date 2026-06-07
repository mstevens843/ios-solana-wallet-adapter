import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Jupiter Mobile dApp-side adapter for the **jWA profile** of iWA v0.1
/// (custom-scheme transport). See `spec/jwa-protocol.md`.
///
/// ## Status — read before shipping
///
/// Jupiter Mobile does **not** yet ship a jWA-conformant wallet-side handler, so
/// against the real Jupiter app `connect` opens the app but signing requests are
/// not honored (the user's device testing confirmed "invalid uri path"). This
/// provider is therefore:
///
/// - **Opt-in** and deliberately **excluded** from
///   `WalletProviderRegistry.supportedProviders` (per `docs/research/jupiter.md`).
/// - Flagged with the `jwa:requires-handler` capability identifier.
/// - **Fully functional today against any jWA-conformant wallet** — proven
///   end-to-end by `SolanaWalletAdapterJupiterHandler` + the loopback tests.
/// - Correct against real Jupiter the moment Jupiter adopts the reference handler.
///
/// Auto-return is provided by the wallet honoring `redirect_link` (the normative
/// jWA return contract); the dApp side here is identical to Phantom/Solflare/
/// Backpack apart from the custom-scheme transport.
public struct JupiterAdapter: WalletProvider {
    public let walletId = "jupiter"

    /// Jupiter publishes no signing universal-link host; the jWA profile is
    /// addressed purely via the custom scheme, so this is intentionally empty.
    public let universalLinkHost = ""
    public let customScheme = "jupiter"

    public init() {}

    /// jWA uses the custom-scheme transport for every method (connect + signing).
    public var deeplinkTransport: DeeplinkURL.Transport { .customScheme }

    public var capabilities: WalletProviderCapabilities {
        WalletProviderCapabilities(
            walletId: walletId,
            displayName: "Jupiter Mobile",
            universalLinkHost: universalLinkHost,
            customScheme: customScheme,
            methods: [
                .init(method: .connect),
                .init(method: .disconnect),
                .init(method: .signMessage),
                .init(method: .signTransaction),
                .init(method: .signAllTransactions),
                .init(method: .signAndSendTransaction),
            ],
            featureIdentifiers: ["jwa:requires-handler"]
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
            transport: deeplinkTransport,
            params: [
                ("app_url", request.appURL.absoluteString),
                ("dapp_encryption_public_key", request.dappEncryptionPublicKey),
                ("redirect_link", request.redirectLink.absoluteString),
                ("cluster", request.cluster.rawValue),
            ]
        )
    }
}
