import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom

final class LoggingTests: XCTestCase {
    private let dapp = EphemeralKeypair(
        publicKey: Base58.decode("WpSggvhoqoVW4XJvfjsB52dvVunYSQWrz6XiuMQVsCf")!,
        secretKey: Base58.decode("4wBqpZM9xaSheZzJSMawUKKwhdpChKbZ5eu5ky4Vigw")!
    )
    private let wallet = EphemeralKeypair(
        publicKey: Base58.decode("6rvZvM15TRkYozYPXwXPiAMFpXPmiVoTPtCT6uqSLd1X")!,
        secretKey: Base58.decode("7ppk9w8NHnH6ehajvJyU31VcMafwZ3ybRtJWumSyD2wd")!
    )
    private let nonce = Base58.decode("KPym5Vq98pYDgiKHQQu8Ty122PDwRNgJ3")!
    private let redirect = URL(string: "myapp://wallet/callback")!
    private let appURL = URL(string: "https://example.com")!

    func testLogConfigurationParsesEnvironmentFlags() {
        let configuration = WalletAdapterLogConfiguration.fromEnvironment([
            "SOLANA_WALLET_ADAPTER_LOG_LEVEL": "debug",
            "SOLANA_WALLET_ADAPTER_UNSAFE_LOGS": "on",
            "SOLANA_WALLET_ADAPTER_LOG_PREFIX": "[iWA Test]",
        ])

        XCTAssertEqual(configuration.logLevel, .debug)
        XCTAssertEqual(configuration.payloadPolicy, .unsafeRawPayloads)
        XCTAssertEqual(configuration.prefix, "[iWA Test]")
    }

    func testLogConfigurationKeepsSafeDefaultsWhenEnvironmentIsMissing() {
        let configuration = WalletAdapterLogConfiguration.fromEnvironment([:])

        XCTAssertEqual(configuration.logLevel, .off)
        XCTAssertEqual(configuration.payloadPolicy, .redacted)
        XCTAssertEqual(configuration.prefix, "[iWA]")
    }

    func testConnectURLEmitsDeterministicSteps() throws {
        let logger = RecordingLogger()
        let adapter = WalletAdapter(
            provider: PhantomAdapter(),
            keypair: dapp,
            cluster: .devnet,
            logger: logger,
            logLevel: .debug
        )

        _ = try adapter.connectURL(appURL: appURL, redirectLink: redirect)

        let steps = logger.events(method: "connectURL").map(\.step)
        XCTAssertEqual(steps, ["STEP_1_START", "STEP_2_PARAMS", "STEP_3_URL_BUILT"])
        XCTAssertEqual(logger.events(method: "connectURL").first?.metadata["wallet"], "phantom")
        XCTAssertEqual(logger.events(method: "connectURL").first?.metadata["target_cluster"], "devnet")
    }

    func testSigningBeforeConnectLogsInvalidSessionFailure() {
        let logger = RecordingLogger()
        let adapter = WalletAdapter(
            provider: PhantomAdapter(),
            keypair: dapp,
            logger: logger,
            logLevel: .debug
        )

        XCTAssertThrowsError(try adapter.signMessageURL(Data("hello".utf8), redirectLink: redirect))
        let events = logger.events(method: "signMessageURL")
        XCTAssertEqual(events.map(\.step), ["STEP_1_START", "STEP_2_SESSION_FAIL", "STEP_FAIL"])
        XCTAssertEqual(events[1].phase, "FAIL")
        XCTAssertEqual(events[1].message, "no active session")
    }

    func testConnectCallbackLogsDecoderAndSessionStorage() throws {
        let logger = RecordingLogger()
        let adapter = WalletAdapter(
            provider: PhantomAdapter(),
            keypair: dapp,
            cluster: .devnet,
            logger: logger,
            logLevel: .debug
        )
        let callback = try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])

        _ = try adapter.handleConnectCallback(callback)

        XCTAssertTrue(logger.events(method: "handleConnectCallback").map(\.step).contains("STEP_3_SESSION_STORED"))
        XCTAssertTrue(logger.events(component: "WalletResponseDecoder", method: "connectSession").map(\.step).contains("STEP_4_PAYLOAD_DECRYPTED"))
        XCTAssertFalse(logger.formatted().contains("session-123"))
    }

    func testMissingDataCallbackLogsExactFailurePoint() throws {
        let logger = RecordingLogger()
        let adapter = try connectedAdapter(logger: logger)
        var components = URLComponents(string: redirect.absoluteString)!
        components.queryItems = [
            URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
        ]

        XCTAssertThrowsError(try adapter.handleSignMessageCallback(components.url!))

        let decoderEvents = logger.events(component: "WalletResponseDecoder", method: "signMessageResult")
        XCTAssertTrue(decoderEvents.contains { $0.step == "STEP_FAIL" && $0.message == "response missing data" })
    }

    func testSignURLLogsEnvelopeMetricsWithoutSensitivePayloads() throws {
        let logger = RecordingLogger()
        let adapter = try connectedAdapter(logger: logger)

        _ = try adapter.signMessageURL(Data("hello deterministic logs".utf8), redirectLink: redirect)

        let output = logger.formatted()
        XCTAssertTrue(output.contains("message_bytes=24"))
        XCTAssertTrue(output.contains("nonce_chars="))
        XCTAssertTrue(output.contains("payload_chars="))
        XCTAssertFalse(output.contains("hello deterministic logs"))
        XCTAssertFalse(output.contains(Base58.encode(dapp.secretKey)))
        XCTAssertFalse(output.contains("session-123"))
    }

    func testUnsafeRawPayloadModeLogsExactRequestPayloadsButNotSecretKeys() throws {
        let logger = RecordingLogger()
        let adapter = try connectedAdapter(logger: logger, payloadPolicy: .unsafeRawPayloads)

        _ = try adapter.signMessageURL(Data("hello deterministic logs".utf8), redirectLink: redirect)

        let output = logger.formatted()
        XCTAssertTrue(output.contains("payload_json_raw="))
        XCTAssertTrue(output.contains("hello deterministic logs"))
        XCTAssertTrue(output.contains("session-123"))
        XCTAssertTrue(output.contains("nonce_raw="))
        XCTAssertTrue(output.contains("payload_raw="))
        XCTAssertFalse(output.contains(Base58.encode(dapp.secretKey)))
    }

    func testUnsafeRawPayloadModeLogsExactDecryptedCallbackPayloads() throws {
        let logger = RecordingLogger()
        let adapter = try connectedAdapter(logger: logger, payloadPolicy: .unsafeRawPayloads)
        let signature = Data(Array(0..<64).map(UInt8.init))
        let callback = try responseURL(payload: ["signature": Base58.encode(signature)])

        _ = try adapter.handleSignMessageCallback(callback)

        let output = logger.formatted()
        XCTAssertTrue(output.contains("callback_raw=myapp://wallet/callback"))
        XCTAssertTrue(output.contains("payload_json_raw="))
        XCTAssertTrue(output.contains(Base58.encode(signature)))
        XCTAssertFalse(output.contains(Base58.encode(dapp.secretKey)))
    }

    func testWalletErrorLogsCodeMessageAndRawCallbackInUnsafeMode() throws {
        let logger = RecordingLogger()
        let adapter = try connectedAdapter(logger: logger, payloadPolicy: .unsafeRawPayloads)
        var components = URLComponents(string: redirect.absoluteString)!
        components.queryItems = [
            URLQueryItem(name: "errorCode", value: "INVALID_SESSION"),
            URLQueryItem(name: "errorMessage", value: "expired on device"),
        ]

        XCTAssertThrowsError(try adapter.handleSignMessageCallback(components.url!))

        let output = logger.formatted()
        XCTAssertTrue(output.contains("STEP_FAIL_WALLET_ERROR"))
        XCTAssertTrue(output.contains("error_code=INVALID_SESSION"))
        XCTAssertTrue(output.contains("expired on device"))
        XCTAssertTrue(output.contains("callback_raw="))
    }

    func testPrintFormatterUsesExpectedShape() {
        let event = WalletAdapterLogEvent(
            component: "WalletAdapter",
            method: "connectURL",
            step: "STEP_1_START",
            phase: "INFO",
            message: "building connect URL",
            metadata: ["wallet": "phantom", "cluster": "devnet"]
        )

        let formatted = WalletAdapterDebugFormatter.format(event)
        XCTAssertTrue(formatted.hasPrefix("[iWA] [WalletAdapter] connectURL | STEP_1_START"))
        XCTAssertTrue(formatted.contains("cluster=devnet"))
        XCTAssertTrue(formatted.contains("wallet=phantom"))
    }

    private func connectedAdapter(
        logger: RecordingLogger,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) throws -> WalletAdapter {
        let adapter = WalletAdapter(
            provider: PhantomAdapter(),
            keypair: dapp,
            cluster: .devnet,
            logger: logger,
            logLevel: .debug,
            payloadPolicy: payloadPolicy
        )
        let callback = try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])
        _ = try adapter.handleConnectCallback(callback)
        logger.clear()
        return adapter
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
}

final class RecordingLogger: WalletAdapterLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [WalletAdapterLogEvent] = []

    func log(_ event: WalletAdapterLogEvent) {
        lock.lock()
        recorded.append(event)
        lock.unlock()
    }

    func events(component: String? = nil, method: String? = nil) -> [WalletAdapterLogEvent] {
        lock.lock()
        let result = recorded.filter { event in
            (component == nil || event.component == component) &&
                (method == nil || event.method == method)
        }
        lock.unlock()
        return result
    }

    func formatted() -> String {
        lock.lock()
        let result = recorded.map { WalletAdapterDebugFormatter.format($0) }.joined(separator: "\n")
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        recorded.removeAll()
        lock.unlock()
    }
}
