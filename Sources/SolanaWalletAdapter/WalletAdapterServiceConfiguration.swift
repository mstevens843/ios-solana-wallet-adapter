import Foundation

/// Runtime network configuration shared by apps that use iWA signing alongside
/// Solana RPC or Jupiter HTTP calls.
public struct WalletAdapterServiceConfiguration: Sendable, Equatable, CustomStringConvertible {
    public static let clusterEnvironmentKey = "SOLANA_CLUSTER"
    public static let solanaRPCURLEnvironmentKey = "SOLANA_RPC_URL"
    public static let heliusRPCURLEnvironmentKey = "HELIUS_RPC_URL"
    public static let jupiterAPIURLEnvironmentKey = "JUP_API_URL"
    public static let jupiterAPIKeyEnvironmentKey = "JUP_API_KEY"
    public static let jupiterAPIKeyAliasEnvironmentKey = "JUPITER_API_KEY"
    public static let jupiterFetchTimeoutEnvironmentKey = "JUP_FETCH_TIMEOUT_MS"
    public static let walletConnectProjectIDEnvironmentKey = "WALLETCONNECT_PROJECT_ID"

    public static let defaultSolanaRPCURL = URL(string: "https://api.mainnet-beta.solana.com")!
    public static let defaultJupiterFetchTimeoutMilliseconds = 8_000

    public enum RPCURLSource: String, Sendable, Equatable, Codable {
        case solanaRPCURL = "SOLANA_RPC_URL"
        case heliusRPCURL = "HELIUS_RPC_URL"
        case publicMainnetDefault = "public_mainnet_default"
    }

    public let cluster: Cluster
    public let solanaRPCURL: URL
    public let solanaRPCURLSource: RPCURLSource
    public let heliusRPCURL: URL?
    public let jupiter: JupiterAPIConfiguration
    public let jupiterFetchTimeoutMilliseconds: Int
    /// Opaque Reown/WalletConnect project id used by the Jupiter Mobile
    /// (WalletConnect) signing path. `nil` when unset. Never logged raw.
    public let walletConnectProjectID: String?

    public init(
        cluster: Cluster = .mainnetBeta,
        solanaRPCURL: URL = Self.defaultSolanaRPCURL,
        solanaRPCURLSource: RPCURLSource = .publicMainnetDefault,
        heliusRPCURL: URL? = nil,
        jupiter: JupiterAPIConfiguration = .defaultConfiguration,
        jupiterFetchTimeoutMilliseconds: Int = Self.defaultJupiterFetchTimeoutMilliseconds,
        walletConnectProjectID: String? = nil
    ) throws {
        try Self.validateHTTPURL(solanaRPCURL, environmentKey: Self.solanaRPCURLEnvironmentKey, allowsQuery: true)
        if let heliusRPCURL {
            try Self.validateHTTPURL(heliusRPCURL, environmentKey: Self.heliusRPCURLEnvironmentKey, allowsQuery: true)
        }
        guard jupiterFetchTimeoutMilliseconds > 0 else {
            throw WalletAdapterError.malformedPayload("\(Self.jupiterFetchTimeoutEnvironmentKey) must be a positive integer.")
        }
        self.cluster = cluster
        self.solanaRPCURL = solanaRPCURL
        self.solanaRPCURLSource = solanaRPCURLSource
        self.heliusRPCURL = heliusRPCURL
        self.jupiter = jupiter
        self.jupiterFetchTimeoutMilliseconds = jupiterFetchTimeoutMilliseconds
        self.walletConnectProjectID = Self.nonEmpty(walletConnectProjectID)
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultCluster: Cluster = .mainnetBeta,
        defaultSolanaRPCURL: URL = Self.defaultSolanaRPCURL,
        defaultJupiterAPIBaseURL: URL = JupiterAPIConfiguration.defaultBaseURL,
        defaultJupiterFetchTimeoutMilliseconds: Int = Self.defaultJupiterFetchTimeoutMilliseconds
    ) throws -> WalletAdapterServiceConfiguration {
        let cluster = try parseCluster(
            environment[clusterEnvironmentKey],
            defaultCluster: defaultCluster
        )
        let solanaRPCURL = try parseOptionalHTTPURL(
            environment[solanaRPCURLEnvironmentKey],
            environmentKey: solanaRPCURLEnvironmentKey,
            allowsQuery: true
        )
        let heliusRPCURL = try parseOptionalHTTPURL(
            environment[heliusRPCURLEnvironmentKey],
            environmentKey: heliusRPCURLEnvironmentKey,
            allowsQuery: true
        )
        let jupiterBaseURL = try parseOptionalHTTPURL(
            environment[jupiterAPIURLEnvironmentKey],
            environmentKey: jupiterAPIURLEnvironmentKey,
            allowsQuery: false
        ) ?? defaultJupiterAPIBaseURL
        let timeoutMilliseconds = try parsePositiveInteger(
            environment[jupiterFetchTimeoutEnvironmentKey],
            environmentKey: jupiterFetchTimeoutEnvironmentKey
        ) ?? defaultJupiterFetchTimeoutMilliseconds
        let walletConnectProjectID = nonEmpty(environment[walletConnectProjectIDEnvironmentKey])

        let resolvedRPCURL: URL
        let source: RPCURLSource
        if let solanaRPCURL {
            resolvedRPCURL = solanaRPCURL
            source = .solanaRPCURL
        } else if let heliusRPCURL {
            resolvedRPCURL = heliusRPCURL
            source = .heliusRPCURL
        } else {
            resolvedRPCURL = defaultSolanaRPCURL
            source = .publicMainnetDefault
        }

        let jupiter = try JupiterAPIConfiguration(
            baseURL: jupiterBaseURL,
            apiKey: firstNonEmpty(
                environment[jupiterAPIKeyEnvironmentKey],
                environment[jupiterAPIKeyAliasEnvironmentKey]
            ),
            apiKeySource: jupiterAPIKeySource(environment)
        )

        return try WalletAdapterServiceConfiguration(
            cluster: cluster,
            solanaRPCURL: resolvedRPCURL,
            solanaRPCURLSource: source,
            heliusRPCURL: heliusRPCURL,
            jupiter: jupiter,
            jupiterFetchTimeoutMilliseconds: timeoutMilliseconds,
            walletConnectProjectID: walletConnectProjectID
        )
    }

    public var jupiterFetchTimeout: TimeInterval {
        TimeInterval(jupiterFetchTimeoutMilliseconds) / 1_000
    }

    public var sanitizedMetadata: [String: String] {
        [
            "cluster": cluster.rawValue,
            "solana_rpc_url": WalletAdapterDebugFormatter.urlShape(solanaRPCURL),
            "solana_rpc_source": solanaRPCURLSource.rawValue,
            "helius_rpc_present": "\(heliusRPCURL != nil)",
            "jupiter_api_url": WalletAdapterDebugFormatter.urlShape(jupiter.baseURL),
            "jupiter_api_key_present": "\(jupiter.apiKey != nil)",
            "jupiter_api_key_source": jupiter.apiKeySource.rawValue,
            "jupiter_fetch_timeout_ms": "\(jupiterFetchTimeoutMilliseconds)",
            "walletconnect_project_id_present": "\(walletConnectProjectID != nil)",
            "walletconnect_project_id_chars": "\(walletConnectProjectID?.count ?? 0)",
        ]
    }

    public var description: String {
        WalletAdapterDebugFormatter.json(sanitizedMetadata)
    }

    private static func parseCluster(_ value: String?, defaultCluster: Cluster) throws -> Cluster {
        guard let value = nonEmpty(value) else { return defaultCluster }
        if let cluster = Cluster(environmentValue: value) {
            return cluster
        }
        throw WalletAdapterError.malformedPayload("\(clusterEnvironmentKey) must be one of mainnet-beta, devnet, or testnet.")
    }

    private static func parseOptionalHTTPURL(_ value: String?, environmentKey: String, allowsQuery: Bool) throws -> URL? {
        guard let value = nonEmpty(value) else { return nil }
        guard let url = URL(string: value) else {
            throw WalletAdapterError.malformedPayload("\(environmentKey) must be a valid http(s) URL.")
        }
        try validateHTTPURL(url, environmentKey: environmentKey, allowsQuery: allowsQuery)
        return url
    }

    private static func validateHTTPURL(_ url: URL, environmentKey: String, allowsQuery: Bool) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            throw WalletAdapterError.malformedPayload("\(environmentKey) must be a valid http(s) URL.")
        }
        if !allowsQuery, URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty == false {
            throw WalletAdapterError.malformedPayload("\(environmentKey) must be a base URL without query parameters.")
        }
    }

    private static func parsePositiveInteger(_ value: String?, environmentKey: String) throws -> Int? {
        guard let value = nonEmpty(value) else { return nil }
        guard let parsed = Int(value), parsed > 0 else {
            throw WalletAdapterError.malformedPayload("\(environmentKey) must be a positive integer.")
        }
        return parsed
    }

    private static func jupiterAPIKeySource(_ environment: [String: String]) -> JupiterAPIConfiguration.APIKeySource {
        if nonEmpty(environment[jupiterAPIKeyEnvironmentKey]) != nil {
            return .jupAPIKey
        }
        if nonEmpty(environment[jupiterAPIKeyAliasEnvironmentKey]) != nil {
            return .jupiterAPIKey
        }
        return .none
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(nonEmpty).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct JupiterAPIConfiguration: Sendable, Equatable, CustomStringConvertible {
    public static let defaultBaseURL = URL(string: "https://api.jup.ag")!
    public static let defaultConfiguration = JupiterAPIConfiguration(uncheckedBaseURL: defaultBaseURL)

    public enum APIKeySource: String, Sendable, Equatable, Codable {
        case none
        case jupAPIKey = "JUP_API_KEY"
        case jupiterAPIKey = "JUPITER_API_KEY"
        case explicit
    }

    public let baseURL: URL
    public let apiKey: String?
    public let apiKeySource: APIKeySource

    private init(uncheckedBaseURL: URL) {
        self.baseURL = uncheckedBaseURL
        self.apiKey = nil
        self.apiKeySource = .none
    }

    public init(
        baseURL: URL = Self.defaultBaseURL,
        apiKey: String? = nil,
        apiKeySource: APIKeySource = .none
    ) throws {
        try Self.validateBaseURL(baseURL)
        self.baseURL = baseURL
        self.apiKey = Self.nonEmpty(apiKey)
        self.apiKeySource = Self.nonEmpty(apiKey) == nil ? .none : apiKeySource
    }

    public var requestHeaders: [String: String] {
        guard let apiKey else { return [:] }
        return ["x-api-key": apiKey]
    }

    public var redactedRequestHeaders: [String: String] {
        guard apiKey != nil else { return [:] }
        return ["x-api-key": "[redacted]"]
    }

    public var sanitizedMetadata: [String: String] {
        [
            "jupiter_api_url": WalletAdapterDebugFormatter.urlShape(baseURL),
            "jupiter_api_key_present": "\(apiKey != nil)",
            "jupiter_api_key_source": apiKeySource.rawValue,
            "jupiter_header_x_api_key_present": "\(apiKey != nil)",
        ]
    }

    public var description: String {
        WalletAdapterDebugFormatter.json(sanitizedMetadata)
    }

    public func quoteURL(
        inputMint: String,
        outputMint: String,
        amount: UInt64,
        slippageBps: Int
    ) throws -> URL {
        try endpoint(
            pathComponents: ["swap", "v1", "quote"],
            queryItems: [
                URLQueryItem(name: "inputMint", value: inputMint),
                URLQueryItem(name: "outputMint", value: outputMint),
                URLQueryItem(name: "amount", value: "\(amount)"),
                URLQueryItem(name: "slippageBps", value: "\(slippageBps)"),
            ]
        )
    }

    public func swapURL() throws -> URL {
        try endpoint(pathComponents: ["swap", "v1", "swap"])
    }

    public func tokenSearchURL(query: String) throws -> URL {
        try endpoint(
            pathComponents: ["tokens", "v2", "search"],
            queryItems: [URLQueryItem(name: "query", value: query)]
        )
    }

    private func endpoint(pathComponents: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WalletAdapterError.malformedPayload("Jupiter base URL could not be converted to URLComponents.")
        }
        let existingPath = components.path
            .split(separator: "/")
            .map(String.init)
        components.path = "/" + (existingPath + pathComponents).joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw WalletAdapterError.malformedPayload("Jupiter endpoint URL could not be built.")
        }
        return url
    }

    private static func validateBaseURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            throw WalletAdapterError.malformedPayload("JUP_API_URL must be a valid http(s) base URL.")
        }
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty == false {
            throw WalletAdapterError.malformedPayload("JUP_API_URL must be a base URL without query parameters.")
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
