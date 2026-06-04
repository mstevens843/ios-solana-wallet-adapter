import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterBackpack
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare
import SolanaWalletAdapterUI

@MainActor
final class WalletAdapterClientTests: XCTestCase {
    private let dapp = EphemeralKeypair(
        publicKey: Base58.decode("WpSggvhoqoVW4XJvfjsB52dvVunYSQWrz6XiuMQVsCf")!,
        secretKey: Base58.decode("4wBqpZM9xaSheZzJSMawUKKwhdpChKbZ5eu5ky4Vigw")!
    )
    private let wallet = EphemeralKeypair(
        publicKey: Base58.decode("6rvZvM15TRkYozYPXwXPiAMFpXPmiVoTPtCT6uqSLd1X")!,
        secretKey: Base58.decode("7ppk9w8NHnH6ehajvJyU31VcMafwZ3ybRtJWumSyD2wd")!
    )
    private let nonce = Base58.decode("KPym5Vq98pYDgiKHQQu8Ty122PDwRNgJ3")!
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    func testConnectAwaitsOpenURLCallbackAndPersistsState() async throws {
        let opener = RecordingOpener()
        let stateStore = MemoryStateStore()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener,
            stateStore: stateStore
        )

        let task = Task { try await client.connect() }
        try await waitForOpenURL(opener)
        let callback = try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])
        XCTAssertTrue(client.handleOpenURL(callback))

        let session = try await task.value
        XCTAssertEqual(session.token, "session-123")
        XCTAssertEqual(stateStore.state?.session?.token, "session-123")
        XCTAssertEqual(opener.openedURLs.first?.host, "phantom.app")
    }

    func testFailedOpenURLMapsToWalletUnreachable() async throws {
        let opener = RecordingOpener(shouldOpen: false)
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )

        do {
            _ = try await client.connect()
            XCTFail("connect should fail when the URL opener rejects the wallet URL")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .walletUnreachable)
        }
    }

    func testClientLogsFlowIDsFailureHintsAndUnsafeResults() async throws {
        let opener = RecordingOpener(shouldOpen: false)
        let logger = RecordingLogger()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener,
            logger: logger,
            logLevel: .debug,
            payloadPolicy: .unsafeRawPayloads
        )

        do {
            _ = try await client.connect()
            XCTFail("connect should fail when the URL opener rejects the wallet URL")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .walletUnreachable)
        }

        let failure = try XCTUnwrap(logger.events(component: "WalletAdapterClient", method: "openOrFail").first { $0.step == "STEP_FAIL_OPEN_URL" })
        XCTAssertEqual(failure.metadata["flow_id"], "connect-1")
        XCTAssertEqual(failure.metadata["error_code"], "WALLET_UNREACHABLE")
        XCTAssertNotNil(failure.metadata["failure_hint"])
        XCTAssertNotNil(failure.metadata["fix_hint"])
        XCTAssertTrue(failure.metadata["url_raw"]?.contains("phantom.app/ul/v1/connect") == true)
    }

    func testClientLogsUnsafeCallbackResultsWithMatchingFlowID() async throws {
        let opener = RecordingOpener()
        let logger = RecordingLogger()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener,
            logger: logger,
            logLevel: .debug,
            payloadPolicy: .unsafeRawPayloads
        )

        let connect = Task { try await client.connect() }
        try await waitForOpenURL(opener)
        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: [
            "public_key": "User1111111111111111111111111111111111",
            "session": "session-123",
        ])))
        _ = try await connect.value

        let connectSuccess = try XCTUnwrap(logger.events(component: "WalletAdapterClient", method: "handleOpenURL").first { $0.metadata["pending"] == "connect" && $0.step == "STEP_2_RESUME_SUCCESS" })
        XCTAssertEqual(connectSuccess.metadata["flow_id"], "connect-1")
        XCTAssertEqual(connectSuccess.metadata["session_token_raw"], "session-123")

        logger.clear()
        let signature = Data(Array(0..<64).map(UInt8.init))
        let sign = Task { try await client.signMessage(Data("hello".utf8)) }
        try await waitForOpenedURLCount(opener, 2)
        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["signature": Base58.encode(signature)])))
        _ = try await sign.value

        let signSuccess = try XCTUnwrap(logger.events(component: "WalletAdapterClient", method: "handleOpenURL").first { $0.metadata["pending"] == "signMessage" && $0.step == "STEP_2_RESUME_SUCCESS" })
        XCTAssertEqual(signSuccess.metadata["flow_id"], "signMessage-2")
        XCTAssertEqual(signSuccess.metadata["signature_raw"], Base58.encode(signature))
        XCTAssertTrue(logger.formatted().contains("message_raw=hello"))
    }

    func testSecondRequestIsRejectedWhileCallbackIsPending() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )

        let task = Task { try await client.connect() }
        try await waitForOpenURL(opener)

        do {
            _ = try await client.signMessage(Data("hello".utf8))
            XCTFail("signMessage should be rejected while connect is pending")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .operationInProgress)
        }

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])))
        _ = try await task.value
    }

    func testHandleOpenURLReturnsFalseWithoutPendingRequest() {
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )

        XCTAssertFalse(client.handleOpenURL(redirect))
    }

    func testHandleOpenURLIgnoresUnrelatedCallbackWithoutClearingPendingRequest() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )

        let task = Task { try await client.connect() }
        try await waitForOpenURL(opener)

        XCTAssertFalse(client.handleOpenURL(URL(string: "iwademo://other/callback?data=ignored")!))
        do {
            _ = try await client.signMessage(Data("hello".utf8))
            XCTFail("signMessage should still be rejected because connect is pending")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .operationInProgress)
        }

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])))
        let session = try await task.value
        XCTAssertEqual(session.token, "session-123")
    }

    func testCancelPendingRequestResumesWithRequestCancelled() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )

        let task = Task { try await client.connect() }
        try await waitForOpenURL(opener)

        XCTAssertTrue(client.cancelPendingRequest())
        XCTAssertFalse(client.cancelPendingRequest())
        do {
            _ = try await task.value
            XCTFail("connect should be cancelled")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .requestCancelled)
        }
    }

    func testFailedSigningCallbackDoesNotLogResumeSuccess() async throws {
        let opener = RecordingOpener()
        let logger = RecordingLogger()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener,
            logger: logger,
            logLevel: .debug
        )

        let connect = Task { try await client.connect() }
        try await waitForOpenURL(opener)
        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])))
        _ = try await connect.value
        logger.clear()

        let sign = Task { try await client.signMessage(Data("hello".utf8)) }
        try await waitForOpenedURLCount(opener, 2)
        XCTAssertTrue(client.handleOpenURL(missingDataResponseURL()))

        do {
            _ = try await sign.value
            XCTFail("sign message should fail for malformed callback")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .malformedPayload("Response is missing nonce or data."))
        }
        XCTAssertFalse(logger.events(component: "WalletAdapterClient", method: "handleOpenURL").contains { $0.step == "STEP_2_RESUME_SUCCESS" })
    }

    func testRestoreLoadsPersistedSessionFromStateStore() throws {
        let stateStore = MemoryStateStore()
        stateStore.state = WalletAdapterState(
            providerId: "phantom",
            cluster: .devnet,
            keypair: dapp,
            session: Session(
                walletEncryptionPublicKey: wallet.publicKey,
                token: "session-123",
                userPublicKey: "User1111111111111111111111111111111111"
            )
        )

        let client = try WalletAdapterClient.restore(
            from: stateStore,
            fallbackProvider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )

        XCTAssertEqual(client.adapter.provider.walletId, "phantom")
        XCTAssertEqual(client.adapter.cluster, .devnet)
        XCTAssertEqual(client.adapter.session?.token, "session-123")
        XCTAssertEqual(client.adapter.keypair, dapp)
    }

    func testGetCapabilitiesReportsNativeMWAStyleMethods() async throws {
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )

        let capabilities = try await client.getCapabilities()

        XCTAssertEqual(capabilities.walletId, "phantom")
        XCTAssertEqual(capabilities.displayName, "Phantom")
        XCTAssertEqual(capabilities.transport, .nativeDeeplink)
        XCTAssertEqual(capabilities.universalLinkHost, "phantom.app")
        XCTAssertEqual(capabilities.customScheme, "phantom")
        XCTAssertTrue(capabilities.support(for: .getCapabilities)?.isSupported == true)
        XCTAssertTrue(capabilities.support(for: .signInWithSolana)?.isSupported == true)
        XCTAssertTrue(capabilities.support(for: .authorize)?.isSupported == true)
        XCTAssertTrue(capabilities.support(for: .signMessages)?.isSupported == true)
        XCTAssertEqual(capabilities.limits.maxMessagesPerRequest, 1)
        XCTAssertEqual(capabilities.limits.maxSignAndSendTransactionsPerRequest, 1)
        XCTAssertTrue(capabilities.support(for: .signAndSendTransaction)?.isDeprecated == true)
        XCTAssertTrue(capabilities.featureIdentifiers.contains("iwa:native-deeplink"))
    }

    func testGetCapabilitiesReportsSolflareAndBackpackNativeMethods() async throws {
        let solflare = WalletAdapterClient(
            provider: SolflareAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )
        let backpack = WalletAdapterClient(
            provider: BackpackAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )

        let solflareCapabilities = try await solflare.getCapabilities()
        let backpackCapabilities = try await backpack.getCapabilities()

        XCTAssertEqual(solflareCapabilities.walletId, "solflare")
        XCTAssertEqual(solflareCapabilities.transport, .nativeDeeplink)
        XCTAssertEqual(solflareCapabilities.support(for: .signInWithSolana)?.isSupported, true)
        XCTAssertEqual(solflareCapabilities.support(for: .signAndSendTransaction)?.isDeprecated, false)
        XCTAssertTrue(solflareCapabilities.featureIdentifiers.contains("solana:sign-message"))

        XCTAssertEqual(backpackCapabilities.walletId, "backpack")
        XCTAssertEqual(backpackCapabilities.transport, .nativeDeeplink)
        XCTAssertEqual(backpackCapabilities.support(for: .signInWithSolana)?.isSupported, true)
        XCTAssertEqual(backpackCapabilities.support(for: .signAndSendTransaction)?.isDeprecated, false)
        XCTAssertTrue(backpackCapabilities.featureIdentifiers.contains("solana:sign-transaction"))
    }

    func testSignInWithSolanaConnectsThenSignsSIWSMessage() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )
        let signature = Data(Array(0..<64).map(UInt8.init))
        let input = SignInWithSolanaInput(
            nonce: "bZQJ0SL6gJ",
            domain: "example.com",
            statement: "Sign in to the demo.",
            uri: appURL,
            issuedAt: date("2022-10-25T16:52:02.748Z")
        )

        let task = Task { try await client.signInWithSolana(input, cluster: .devnet) }
        try await waitForOpenedURLCount(opener, 1)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/connect")

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: [
            "public_key": "User1111111111111111111111111111111111",
            "session": "session-123",
        ])))
        try await waitForOpenedURLCount(opener, 2)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[1], resolvingAgainstBaseURL: false)?.path, "/ul/v1/signMessage")

        let requestPayload = try decryptRequestPayload(opener.openedURLs[1])
        let encodedMessage = try XCTUnwrap(requestPayload["message"] as? String)
        let messageData = try XCTUnwrap(Base58.decode(encodedMessage))
        let message = try XCTUnwrap(String(data: messageData, encoding: .utf8))
        XCTAssertEqual(requestPayload["display"] as? String, "utf8")
        XCTAssertTrue(message.contains("example.com wants you to sign in with your Solana account:"))
        XCTAssertTrue(message.contains("User1111111111111111111111111111111111"))
        XCTAssertTrue(message.contains("Chain ID: solana:devnet"))
        XCTAssertTrue(message.contains("Nonce: bZQJ0SL6gJ"))

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["signature": Base58.encode(signature)])))
        let result = try await task.value

        XCTAssertEqual(result.account, "User1111111111111111111111111111111111")
        XCTAssertEqual(result.signature, signature)
        XCTAssertEqual(result.signatureType, .ed25519)
        XCTAssertEqual(result.session.token, "session-123")
        XCTAssertEqual(result.signedMessageString, message)
    }

    func testSignInWithSolanaRejectsMismatchedInputChainId() async throws {
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            opener: RecordingOpener()
        )
        let input = SignInWithSolanaInput(nonce: "bZQJ0SL6gJ", chainId: "solana:mainnet")

        do {
            _ = try await client.signInWithSolana(input, cluster: .devnet)
            XCTFail("signInWithSolana should reject a chainId that conflicts with the adapter cluster")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .clusterMismatch(expected: .devnet, got: "solana:mainnet"))
        }
    }

    func testCompatibilityAliasesRejectUnsupportedNativeBatches() async throws {
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener()
        )

        do {
            _ = try await client.signMessages([Data([1]), Data([2])])
            XCTFail("native deeplink signMessages should reject batches")
        } catch {
            XCTAssertEqual(
                error as? WalletAdapterError,
                .unsupportedMethod("signMessages currently supports exactly one message on native iOS deeplinks.")
            )
        }

        do {
            _ = try await client.signAndSendTransactions([Data([1]), Data([2])])
            XCTFail("native deeplink signAndSendTransactions should reject batches")
        } catch {
            XCTAssertEqual(
                error as? WalletAdapterError,
                .unsupportedMethod("signAndSendTransactions currently supports exactly one transaction on native iOS deeplinks.")
            )
        }
    }

    func testCompatibilityAliasLoggingIncludesUnsupportedBatchHints() async throws {
        let logger = RecordingLogger()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            opener: RecordingOpener(),
            logger: logger,
            logLevel: .debug,
            payloadPolicy: .unsafeRawPayloads
        )

        do {
            _ = try await client.signMessages([Data("one".utf8), Data("two".utf8)])
            XCTFail("native deeplink signMessages should reject batches")
        } catch {
            XCTAssertEqual(
                error as? WalletAdapterError,
                .unsupportedMethod("signMessages currently supports exactly one message on native iOS deeplinks.")
            )
        }

        let failure = try XCTUnwrap(logger.events(component: "WalletAdapterClient", method: "signMessages").first {
            $0.step == "STEP_FAIL" && $0.metadata["expected"] == "1"
        })
        XCTAssertEqual(failure.metadata["flow_id"], "signMessages-1")
        XCTAssertEqual(failure.metadata["actual"], "2")
        XCTAssertEqual(failure.metadata["error_code"], "UNSUPPORTED_METHOD")
        XCTAssertNotNil(failure.metadata["failure_hint"])
        XCTAssertTrue(logger.formatted().contains("messages_raw=one,two"))
    }

    func testAuthorizeCompatibilityAliasUsesNativeConnect() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )

        let task = Task { try await client.authorize(cluster: .devnet) }
        try await waitForOpenedURLCount(opener, 1)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/connect")

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: [
            "public_key": "User1111111111111111111111111111111111",
            "session": "session-123",
        ])))
        let session = try await task.value

        XCTAssertEqual(session.token, "session-123")
    }

    func testSingleMessageCompatibilityAliasUsesNativeSignMessage() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: wallet.publicKey,
            token: "session-123",
            userPublicKey: "User1111111111111111111111111111111111"
        ))
        let signature = Data(Array(0..<64).map(UInt8.init))

        let task = Task { try await client.signMessages([Data("hello".utf8)]) }
        try await waitForOpenedURLCount(opener, 1)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/signMessage")

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: ["signature": Base58.encode(signature)])))
        let results = try await task.value

        XCTAssertEqual(results, [SignMessageResult(signature: signature)])
    }

    func testSignTransactionsCompatibilityAliasUsesNativeSignAllTransactions() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: wallet.publicKey,
            token: "session-123",
            userPublicKey: "User1111111111111111111111111111111111"
        ))
        let signedTransactions = [Data([1, 2]), Data([3, 4])]

        let task = Task { try await client.signTransactions([Data([9]), Data([8])]) }
        try await waitForOpenedURLCount(opener, 1)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/signAllTransactions")

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: [
            "transactions": signedTransactions.map(Base58.encode),
        ])))
        let result = try await task.value

        XCTAssertEqual(result.transactions, signedTransactions)
    }

    func testSingleSignAndSendTransactionsCompatibilityAliasUsesNativeSignAndSendTransaction() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: wallet.publicKey,
            token: "session-123",
            userPublicKey: "User1111111111111111111111111111111111"
        ))

        let task = Task { try await client.signAndSendTransactions([Data([1, 2, 3])]) }
        try await waitForOpenedURLCount(opener, 1)
        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/signAndSendTransaction")

        XCTAssertTrue(client.handleOpenURL(try responseURL(payload: [
            "signature": "Txid111111111111111111111111111111111111",
        ])))
        let results = try await task.value

        XCTAssertEqual(results, [SignAndSendTransactionResult(signature: "Txid111111111111111111111111111111111111")])
    }

    func testDeauthorizeCompatibilityAliasClearsSession() async throws {
        let opener = RecordingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .devnet,
            keypair: dapp,
            opener: opener
        )
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: wallet.publicKey,
            token: "session-123",
            userPublicKey: "User1111111111111111111111111111111111"
        ))

        try await client.deauthorize()

        XCTAssertEqual(URLComponents(url: opener.openedURLs[0], resolvingAgainstBaseURL: false)?.path, "/ul/v1/disconnect")
        XCTAssertNil(client.adapter.session)
    }

    private func responseURL(payload: [String: Any]) throws -> URL {
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let box = NaClBox.seal(message: plaintext, nonce: nonce, theirPublicKey: dapp.publicKey, mySecretKey: wallet.secretKey)
        var components = URLComponents(string: redirect.absoluteString)!
        components.queryItems = [
            URLQueryItem(name: "phantom_encryption_public_key", value: Base58.encode(wallet.publicKey)),
            URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
            URLQueryItem(name: "data", value: Base58.encode(box)),
        ]
        return components.url!
    }

    private func decryptRequestPayload(_ url: URL) throws -> [String: Any] {
        let params = queryParams(url)
        let requestNonce = try XCTUnwrap(Base58.decode(try XCTUnwrap(params["nonce"])))
        let box = try XCTUnwrap(Base58.decode(try XCTUnwrap(params["payload"])))
        let plaintext = try XCTUnwrap(NaClBox.open(
            box: box,
            nonce: requestNonce,
            theirPublicKey: dapp.publicKey,
            mySecretKey: wallet.secretKey
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
    }

    private func queryParams(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }

    private func missingDataResponseURL() -> URL {
        var components = URLComponents(string: redirect.absoluteString)!
        components.queryItems = [
            URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
        ]
        return components.url!
    }

    private func waitForOpenURL(_ opener: RecordingOpener) async throws {
        try await waitForOpenedURLCount(opener, 1)
    }

    private func waitForOpenedURLCount(_ opener: RecordingOpener, _ count: Int) async throws {
        for _ in 0..<50 {
            if opener.openedURLs.count >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("wallet URL was not opened")
    }
}

@MainActor
private final class RecordingOpener: WalletURLOpening {
    let shouldOpen: Bool
    private(set) var openedURLs: [URL] = []

    init(shouldOpen: Bool = true) {
        self.shouldOpen = shouldOpen
    }

    func openWalletURL(_ url: URL) async -> Bool {
        openedURLs.append(url)
        return shouldOpen
    }
}

private final class MemoryStateStore: WalletAdapterStateStore, @unchecked Sendable {
    var state: WalletAdapterState?

    func loadState() throws -> WalletAdapterState? {
        state
    }

    func saveState(_ state: WalletAdapterState?) throws {
        self.state = state
    }
}
