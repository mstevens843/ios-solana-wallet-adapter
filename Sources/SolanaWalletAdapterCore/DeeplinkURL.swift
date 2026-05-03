import Foundation

/// Builds wallet deeplink URLs of the form
/// `https://<host>/ul/<version>/<method>?<query>`.
///
/// Phantom, Solflare, and Backpack share this shape (see `docs/research/`).
/// Per-wallet adapters call into `make` rather than hand-rolling URL strings,
/// so any later spec adjustment lands in one place.
public enum DeeplinkURL {
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
    public static func make(host: WalletHost, method: String, params: [(String, String)]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.universalLinkHost
        components.path = "/ul/\(host.version)/\(method)"
        components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}
