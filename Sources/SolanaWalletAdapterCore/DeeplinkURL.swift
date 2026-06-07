import Foundation

/// Builds wallet deeplink URLs for the two iWA transports:
///
/// - `.universalLink` (default): `https://<host>/ul/<version>/<method>?<query>` —
///   Phantom, Solflare, and Backpack share this shape (see `docs/research/`).
/// - `.customScheme`: `<scheme>://<version>/<method>?<query>` — used by the jWA
///   profile for wallets that publish no signing universal-link host (e.g.
///   Jupiter Mobile). See `spec/jwa-protocol.md`.
///
/// Per-wallet adapters call into `make` rather than hand-rolling URL strings,
/// so any later spec adjustment lands in one place.
public enum DeeplinkURL {
    /// How a deeplink request URL is addressed to the wallet.
    public enum Transport: String, Sendable, Equatable {
        /// `https://<universalLinkHost>/ul/<version>/<method>`.
        case universalLink
        /// `<customScheme>://<version>/<method>`.
        case customScheme
    }

    public struct WalletHost: Sendable {
        public let universalLinkHost: String   // e.g. "phantom.app"
        public let customScheme: String        // e.g. "phantom"
        public let version: String             // e.g. "v1"

        public init(universalLinkHost: String, customScheme: String, version: String = "v1") {
            self.universalLinkHost = universalLinkHost
            self.customScheme = customScheme
            self.version = version
        }
    }

    /// Parameters get URL-encoded by `URLComponents`; callers pass raw strings.
    /// The order of items is preserved which keeps test expectations stable.
    ///
    /// `transport` defaults to `.universalLink` so existing callers
    /// (Phantom/Solflare/Backpack) are unaffected.
    public static func make(
        host: WalletHost,
        method: String,
        transport: Transport = .universalLink,
        params: [(String, String)]
    ) throws -> URL {
        var components = URLComponents()
        switch transport {
        case .universalLink:
            components.scheme = "https"
            components.host = host.universalLinkHost
            components.path = "/ul/\(host.version)/\(method)"
        case .customScheme:
            // e.g. jupiter://v1/connect — the version is the authority so the
            // method stays the single trailing path component (kept consistent
            // with the universal-link shape for wallet-side method parsing).
            components.scheme = host.customScheme
            components.host = host.version
            components.path = "/\(method)"
        }
        components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}
