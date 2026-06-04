import XCTest
import SolanaWalletAdapter

final class WalletAdapterServiceConfigurationTests: XCTestCase {
    func testDefaultsUseMainnetRPCAndJupiterBaseURL() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([:])

        XCTAssertEqual(configuration.cluster, .mainnetBeta)
        XCTAssertEqual(configuration.solanaRPCURL.absoluteString, "https://api.mainnet-beta.solana.com")
        XCTAssertEqual(configuration.solanaRPCURLSource, .publicMainnetDefault)
        XCTAssertNil(configuration.heliusRPCURL)
        XCTAssertEqual(configuration.jupiter.baseURL.absoluteString, "https://api.jup.ag")
        XCTAssertNil(configuration.jupiter.apiKey)
        XCTAssertEqual(configuration.jupiter.apiKeySource, .none)
        XCTAssertEqual(configuration.jupiterFetchTimeoutMilliseconds, 8_000)
        XCTAssertNil(configuration.walletConnectProjectID)
    }

    func testWalletConnectProjectIDParsesAndSanitizesWithoutLeakingRawID() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "WALLETCONNECT_PROJECT_ID": "7c5434a4b0dffb44ae4344c1da2f9825",
        ])

        XCTAssertEqual(configuration.walletConnectProjectID, "7c5434a4b0dffb44ae4344c1da2f9825")
        XCTAssertEqual(configuration.sanitizedMetadata["walletconnect_project_id_present"], "true")
        XCTAssertEqual(configuration.sanitizedMetadata["walletconnect_project_id_chars"], "32")
        XCTAssertFalse(configuration.sanitizedMetadata.values.contains("7c5434a4b0dffb44ae4344c1da2f9825"))
    }

    func testWalletConnectProjectIDAbsentSanitizesToFalse() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([:])

        XCTAssertEqual(configuration.sanitizedMetadata["walletconnect_project_id_present"], "false")
        XCTAssertEqual(configuration.sanitizedMetadata["walletconnect_project_id_chars"], "0")
    }

    func testWalletConnectProjectIDBlankIsTreatedAsNil() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "WALLETCONNECT_PROJECT_ID": "   ",
        ])

        XCTAssertNil(configuration.walletConnectProjectID)
    }

    func testEnvironmentParsesClusterRPCJupiterAndTimeout() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "SOLANA_CLUSTER": "solana:devnet",
            "SOLANA_RPC_URL": "https://rpc.example.com",
            "HELIUS_RPC_URL": "https://mainnet.helius-rpc.com/?api-key=helius-secret",
            "JUP_API_URL": "https://lite-api.jup.ag",
            "JUP_API_KEY": "jupiter-secret",
            "JUP_FETCH_TIMEOUT_MS": "12000",
        ])

        XCTAssertEqual(configuration.cluster, .devnet)
        XCTAssertEqual(configuration.solanaRPCURL.absoluteString, "https://rpc.example.com")
        XCTAssertEqual(configuration.solanaRPCURLSource, .solanaRPCURL)
        XCTAssertEqual(configuration.heliusRPCURL?.host, "mainnet.helius-rpc.com")
        XCTAssertEqual(configuration.jupiter.baseURL.absoluteString, "https://lite-api.jup.ag")
        XCTAssertEqual(configuration.jupiter.apiKey, "jupiter-secret")
        XCTAssertEqual(configuration.jupiter.apiKeySource, .jupAPIKey)
        XCTAssertEqual(configuration.jupiter.requestHeaders["x-api-key"], "jupiter-secret")
        XCTAssertEqual(configuration.jupiter.redactedRequestHeaders["x-api-key"], "[redacted]")
        XCTAssertEqual(configuration.jupiterFetchTimeoutMilliseconds, 12_000)
    }

    func testHeliusRPCIsFallbackWhenSolanaRPCIsMissing() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "HELIUS_RPC_URL": "https://mainnet.helius-rpc.com/?api-key=helius-secret",
        ])

        XCTAssertEqual(configuration.solanaRPCURL.host, "mainnet.helius-rpc.com")
        XCTAssertEqual(configuration.solanaRPCURLSource, .heliusRPCURL)
        XCTAssertEqual(configuration.heliusRPCURL?.absoluteString, configuration.solanaRPCURL.absoluteString)
    }

    func testJupiterKeyAliasIsSupported() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "JUPITER_API_KEY": "alias-secret",
        ])

        XCTAssertEqual(configuration.jupiter.apiKey, "alias-secret")
        XCTAssertEqual(configuration.jupiter.apiKeySource, .jupiterAPIKey)
    }

    func testPrimaryJupiterKeyWinsOverAlias() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "JUP_API_KEY": "primary-secret",
            "JUPITER_API_KEY": "alias-secret",
        ])

        XCTAssertEqual(configuration.jupiter.apiKey, "primary-secret")
        XCTAssertEqual(configuration.jupiter.apiKeySource, .jupAPIKey)
    }

    func testInvalidClusterFailsLoudly() {
        XCTAssertThrowsError(try WalletAdapterServiceConfiguration.fromEnvironment([
            "SOLANA_CLUSTER": "localnet",
        ])) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("SOLANA_CLUSTER must be one of mainnet-beta, devnet, or testnet.")
            )
        }
    }

    func testInvalidURLsFailLoudly() {
        XCTAssertThrowsError(try WalletAdapterServiceConfiguration.fromEnvironment([
            "SOLANA_RPC_URL": "not-a-url",
        ])) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("SOLANA_RPC_URL must be a valid http(s) URL.")
            )
        }

        XCTAssertThrowsError(try WalletAdapterServiceConfiguration.fromEnvironment([
            "JUP_API_URL": "https://api.jup.ag?api-key=secret",
        ])) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("JUP_API_URL must be a base URL without query parameters.")
            )
        }
    }

    func testInvalidTimeoutFailsLoudly() {
        XCTAssertThrowsError(try WalletAdapterServiceConfiguration.fromEnvironment([
            "JUP_FETCH_TIMEOUT_MS": "0",
        ])) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("JUP_FETCH_TIMEOUT_MS must be a positive integer.")
            )
        }
    }

    func testJupiterURLsMatchSolpulseEndpointShape() throws {
        let configuration = try JupiterAPIConfiguration(baseURL: URL(string: "https://api.jup.ag")!)
        let quote = try configuration.quoteURL(
            inputMint: "So11111111111111111111111111111111111111112",
            outputMint: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkYf5p6oUe7dV7b1",
            amount: 1_000_000,
            slippageBps: 50
        )
        let quoteComponents = try XCTUnwrap(URLComponents(url: quote, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (quoteComponents.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(quoteComponents.scheme, "https")
        XCTAssertEqual(quoteComponents.host, "api.jup.ag")
        XCTAssertEqual(quoteComponents.path, "/swap/v1/quote")
        XCTAssertEqual(queryItems["inputMint"], "So11111111111111111111111111111111111111112")
        XCTAssertEqual(queryItems["outputMint"], "Es9vMFrzaCERmJfrF4H2FYD4KCoNkYf5p6oUe7dV7b1")
        XCTAssertEqual(queryItems["amount"], "1000000")
        XCTAssertEqual(queryItems["slippageBps"], "50")

        XCTAssertEqual(try configuration.swapURL().path, "/swap/v1/swap")
        XCTAssertEqual(try configuration.tokenSearchURL(query: "SOL").path, "/tokens/v2/search")
    }

    func testDescriptionsAndMetadataDoNotExposeSecrets() throws {
        let configuration = try WalletAdapterServiceConfiguration.fromEnvironment([
            "SOLANA_RPC_URL": "https://rpc.example.com/?api-key=rpc-secret",
            "HELIUS_RPC_URL": "https://mainnet.helius-rpc.com/?api-key=helius-secret",
            "JUP_API_KEY": "jupiter-secret",
        ])

        let serviceDescription = "\(configuration)"
        let jupiterDescription = "\(configuration.jupiter)"
        let metadata = configuration.sanitizedMetadata.values.joined(separator: " ")

        XCTAssertFalse(serviceDescription.contains("rpc-secret"))
        XCTAssertFalse(serviceDescription.contains("helius-secret"))
        XCTAssertFalse(serviceDescription.contains("jupiter-secret"))
        XCTAssertFalse(jupiterDescription.contains("jupiter-secret"))
        XCTAssertFalse(metadata.contains("rpc-secret"))
        XCTAssertFalse(metadata.contains("helius-secret"))
        XCTAssertFalse(metadata.contains("jupiter-secret"))
        XCTAssertTrue(serviceDescription.contains("query_keys=api-key"))
    }
}
