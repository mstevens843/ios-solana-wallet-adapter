import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterWalletConnect

final class WalletConnectSolanaTests: XCTestCase {
    func testNamespaceProposalUsesWalletConnectSolanaMethods() {
        let namespace = WalletConnectSolanaNamespace.proposal(chains: [.mainnet, .devnet])

        XCTAssertEqual(namespace.chains, ["solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqai"])
        XCTAssertEqual(namespace.events, ["chainChanged", "accountsChanged"])
        XCTAssertTrue(namespace.methods.contains("solana_getAccounts"))
        XCTAssertTrue(namespace.methods.contains("solana_requestAccounts"))
        XCTAssertTrue(namespace.methods.contains("solana_signMessage"))
        XCTAssertTrue(namespace.methods.contains("solana_signTransaction"))
        XCTAssertTrue(namespace.methods.contains("solana_signAllTransactions"))
        XCTAssertTrue(namespace.methods.contains("solana_signAndSendTransaction"))
    }

    func testClusterMapsToWalletConnectChain() {
        XCTAssertEqual(WalletConnectSolanaChain(cluster: .mainnetBeta), .mainnet)
        XCTAssertEqual(WalletConnectSolanaChain(cluster: .devnet), .devnet)
        XCTAssertEqual(WalletConnectSolanaChain(cluster: .testnet), .testnet)
    }

    func testSignMessageRequestUsesBase58MessageAndPubkey() throws {
        let request = WalletConnectSolanaRequests.signMessage(
            Data("hello".utf8),
            pubkey: "AqP3MyNwDP4L1GJKYhzmaAUdrjzpqJUZjahM7kHpgavm",
            id: 7
        )
        let json = try encodedJSONObject(request)

        XCTAssertEqual(json["id"] as? Int, 7)
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "solana_signMessage")
        let params = try XCTUnwrap(json["params"] as? [String: Any])
        XCTAssertEqual(params["message"] as? String, "Cn8eVZg")
        XCTAssertEqual(params["pubkey"] as? String, "AqP3MyNwDP4L1GJKYhzmaAUdrjzpqJUZjahM7kHpgavm")
    }

    func testTransactionRequestsUseBase64Transactions() throws {
        let transaction = Data([0, 1, 2, 3])
        let request = WalletConnectSolanaRequests.signAndSendTransaction(
            transaction,
            sendOptions: .init(skipPreflight: true, preflightCommitment: "confirmed", maxRetries: 3, minContextSlot: 42),
            id: 9
        )
        let json = try encodedJSONObject(request)

        XCTAssertEqual(json["method"] as? String, "solana_signAndSendTransaction")
        let params = try XCTUnwrap(json["params"] as? [String: Any])
        XCTAssertEqual(params["transaction"] as? String, "AAECAw==")
        let sendOptions = try XCTUnwrap(params["sendOptions"] as? [String: Any])
        XCTAssertEqual(sendOptions["skipPreflight"] as? Bool, true)
        XCTAssertEqual(sendOptions["preflightCommitment"] as? String, "confirmed")
        XCTAssertEqual(sendOptions["maxRetries"] as? Int, 3)
        XCTAssertEqual(sendOptions["minContextSlot"] as? Int, 42)
    }

    func testDecodedResultsExposeByteHelpers() throws {
        let signedTransaction = Data([4, 5, 6]).base64EncodedString()
        let data = Data("""
        {
          "id": 1,
          "jsonrpc": "2.0",
          "result": {
            "signature": "5Q",
            "transaction": "\(signedTransaction)"
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(
            WalletConnectSolanaJSONRPCResponse<WalletConnectSolanaSignTransactionResult>.self,
            from: data
        )

        XCTAssertEqual(response.result?.signatureData, Data([0xff]))
        XCTAssertEqual(response.result?.transactionData, Data([4, 5, 6]))
        XCTAssertNil(response.error)
    }

    func testClientUsesTransportSessionAndPrimaryPubkey() async throws {
        let metadata = ReownAppMetadata(
            name: "iWADemo",
            description: "WalletConnect smoke demo",
            url: URL(string: "https://example.com")!,
            icons: [URL(string: "https://example.com/icon.png")!],
            redirect: .init(native: "iwademo://walletconnect")
        )
        let configuration = try ReownProjectConfiguration(projectId: "project-id", metadata: metadata)
        let transport = RecordingWalletConnectTransport()
        let client = WalletConnectSolanaClient(configuration: configuration, transport: transport)

        let session = try await client.connect()
        let signature = try await client.signMessage(Data([0xff]), id: 22)
        let requestedMethods = await transport.requestedMethods
        let requestedChains = await transport.requestedChains

        XCTAssertEqual(session.primaryPubkey, "User1111111111111111111111111111111111")
        XCTAssertEqual(signature.signature, "5Q")
        XCTAssertEqual(requestedMethods, ["solana_signMessage"])
        XCTAssertEqual(requestedChains, ["solana:mainnet"])
    }

    func testClientLogsWalletConnectUnsafeRequestsAndResults() async throws {
        let metadata = ReownAppMetadata(
            name: "iWADemo",
            description: "WalletConnect smoke demo",
            url: URL(string: "https://example.com")!,
            icons: [URL(string: "https://example.com/icon.png")!],
            redirect: .init(native: "iwademo://walletconnect")
        )
        let configuration = try ReownProjectConfiguration(projectId: "project-id", metadata: metadata)
        let transport = RecordingWalletConnectTransport()
        let logger = RecordingLogger()
        let client = WalletConnectSolanaClient(
            configuration: configuration,
            transport: transport,
            logger: logger,
            logLevel: .debug,
            payloadPolicy: .unsafeRawPayloads
        )

        _ = try await client.connect()
        _ = try await client.signMessage(Data("hello".utf8), id: 22)

        let request = try XCTUnwrap(logger.events(component: "WalletConnectSolanaClient", method: "signMessage").first { $0.step == "STEP_3_REQUEST_BUILT" })
        XCTAssertEqual(request.metadata["flow_id"], "signMessage-2")
        XCTAssertEqual(request.metadata["request_id"], "22")
        XCTAssertEqual(request.metadata["jsonrpc_method"], "solana_signMessage")
        XCTAssertTrue(request.metadata["request_json_raw"]?.contains("\"method\":\"solana_signMessage\"") == true)
        XCTAssertTrue(request.metadata["request_json_raw"]?.contains("\"message\":\"Cn8eVZg\"") == true)

        let success = try XCTUnwrap(logger.events(component: "WalletConnectSolanaClient", method: "signMessage").first { $0.step == "STEP_4_SUCCESS" })
        XCTAssertEqual(success.metadata["signature_raw"], "5Q")
        XCTAssertTrue(logger.formatted().contains("accounts_raw=User1111111111111111111111111111111111"))
        XCTAssertFalse(logger.formatted().contains("project-id"))
    }

    func testClientGetsAccountsAndReportsWalletConnectCapabilities() async throws {
        let metadata = ReownAppMetadata(
            name: "iWADemo",
            description: "WalletConnect smoke demo",
            url: URL(string: "https://example.com")!,
            icons: [URL(string: "https://example.com/icon.png")!],
            redirect: .init(native: "iwademo://walletconnect")
        )
        let configuration = try ReownProjectConfiguration(projectId: "project-id", metadata: metadata)
        let transport = RecordingWalletConnectTransport()
        let client = WalletConnectSolanaClient(configuration: configuration, transport: transport)

        let capabilities = try await client.getCapabilities()
        XCTAssertEqual(capabilities.walletId, "walletconnect")
        XCTAssertEqual(capabilities.transport, .walletConnect)
        XCTAssertTrue(capabilities.support(for: .getAccounts)?.isSupported == true)
        XCTAssertTrue(capabilities.support(for: .requestAccounts)?.isSupported == true)
        XCTAssertTrue(capabilities.support(for: .signMessage)?.isSupported == true)
        XCTAssertTrue(capabilities.featureIdentifiers.contains("solana:walletconnect"))

        _ = try await client.connect()
        let accounts = try await client.getAccounts(id: 44)
        let requestedAccounts = try await client.requestAccounts(id: 45)
        let requestedMethods = await transport.requestedMethods

        XCTAssertEqual(accounts.accounts.first?.pubkey, "User1111111111111111111111111111111111")
        XCTAssertEqual(requestedAccounts.accounts.first?.pubkey, "User1111111111111111111111111111111111")
        XCTAssertEqual(requestedMethods, ["solana_getAccounts", "solana_requestAccounts"])
    }

    func testEmptyReownProjectIdIsRejected() {
        let metadata = ReownAppMetadata(
            name: "iWADemo",
            description: "WalletConnect smoke demo",
            url: URL(string: "https://example.com")!,
            icons: []
        )

        XCTAssertThrowsError(try ReownProjectConfiguration(projectId: " ", metadata: metadata))
    }

    func testNotWiredTransportConnectFailsDeterministicallyWithoutLeakingProjectID() async throws {
        let metadata = ReownAppMetadata(
            name: "iWADemo",
            description: "WalletConnect smoke demo",
            url: URL(string: "https://example.com")!,
            icons: []
        )
        let configuration = try ReownProjectConfiguration(
            projectId: "7c5434a4b0dffb44ae4344c1da2f9825",
            metadata: metadata
        )
        let logger = RecordingLogger()
        let client = WalletConnectSolanaClient(
            configuration: configuration,
            transport: NotWiredWalletConnectTransport(),
            logger: logger,
            logLevel: .debug
        )

        do {
            _ = try await client.connect()
            XCTFail("connect should throw WALLETCONNECT_TRANSPORT_NOT_WIRED")
        } catch let WalletAdapterError.other(code, _) {
            XCTAssertEqual(code, NotWiredWalletConnectTransport.errorCode)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let connectEvents = logger.events(component: "WalletConnectSolanaClient", method: "connect")
        let steps = connectEvents.map(\.step)
        XCTAssertTrue(steps.contains("STEP_1_START"))
        XCTAssertTrue(steps.contains("STEP_FAIL"))

        let start = try XCTUnwrap(connectEvents.first { $0.step == "STEP_1_START" })
        XCTAssertEqual(start.metadata["project_id_present"], "true")
        XCTAssertEqual(start.metadata["project_id_chars"], "32")

        let failure = try XCTUnwrap(connectEvents.first { $0.step == "STEP_FAIL" })
        XCTAssertEqual(failure.metadata["wallet_error_code"], NotWiredWalletConnectTransport.errorCode)

        // The raw project id must never appear in the logs.
        XCTAssertFalse(logger.formatted().contains("7c5434a4b0dffb44ae4344c1da2f9825"))
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor RecordingWalletConnectTransport: WalletConnectSolanaTransport {
    private(set) var requestedMethods: [String] = []
    private(set) var requestedChains: [String] = []

    func connect(
        configuration: ReownProjectConfiguration,
        namespace: WalletConnectSolanaNamespace
    ) async throws -> WalletConnectSolanaSession {
        XCTAssertEqual(configuration.projectId, "project-id")
        XCTAssertTrue(namespace.methods.contains("solana_signMessage"))
        return WalletConnectSolanaSession(
            topic: "topic-1",
            chain: "solana:mainnet",
            accounts: [WalletConnectSolanaAccount(pubkey: "User1111111111111111111111111111111111")]
        )
    }

    func request<Params, Result>(
        _ request: WalletConnectSolanaJSONRPCRequest<Params>,
        chain: String,
        session: WalletConnectSolanaSession,
        responseType: Result.Type
    ) async throws -> Result where Params: Sendable & Equatable & Encodable, Result: Sendable & Decodable {
        requestedMethods.append(request.method.rawValue)
        requestedChains.append(chain)
        XCTAssertEqual(session.topic, "topic-1")
        switch request.method {
        case .getAccounts, .requestAccounts:
            guard let result = WalletConnectSolanaAccountsResult(
                accounts: [WalletConnectSolanaAccount(pubkey: "User1111111111111111111111111111111111")]
            ) as? Result else {
                throw WalletAdapterError.unsupportedMethod(request.method.rawValue)
            }
            return result
        case .signMessage:
            guard let result = WalletConnectSolanaSignMessageResult(signature: "5Q") as? Result else {
                throw WalletAdapterError.unsupportedMethod(request.method.rawValue)
            }
            return result
        case .signTransaction, .signAllTransactions, .signAndSendTransaction:
            throw WalletAdapterError.unsupportedMethod(request.method.rawValue)
        }
    }

    func disconnect(session: WalletConnectSolanaSession) async throws {}
}
