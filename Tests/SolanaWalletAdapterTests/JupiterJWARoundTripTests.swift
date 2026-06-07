import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterJupiter
import SolanaWalletAdapterJupiterHandler

/// End-to-end loopback proof of the jWA profile: the dApp-side `JupiterAdapter`
/// builds custom-scheme requests, the wallet-side `JupiterWalletHandler` consumes
/// them, signs, and fires the `redirect_link` callback, and the dApp decodes the
/// result with `WalletResponseDecoder`.
///
/// This validates BOTH the encrypted round-trip AND the auto-return contract on
/// real wire bytes, with no dependency on the real Jupiter app — the handler is a
/// conformant stand-in (the "FakeJupiter" of the loopback design).
@MainActor
final class JupiterJWARoundTripTests: XCTestCase {

    // MARK: - Test doubles

    private struct TestSigner: JWASigner {
        let userPublicKey = "JUP1terUser11111111111111111111111111111111"
        let messageSignature = Data((0..<64).map(UInt8.init))
        let signedTransaction = Data((20..<84).map(UInt8.init))
        let txid = Base58.encode(Data((100..<132).map(UInt8.init)))

        func signMessage(_ message: Data) async throws -> Data { messageSignature }
        func signTransaction(_ transaction: Data) async throws -> Data { signedTransaction }
        func signAllTransactions(_ transactions: [Data]) async throws -> [Data] { transactions.map { _ in signedTransaction } }
        func signAndSendTransaction(_ transaction: Data, options: SendOptions) async throws -> String { txid }
    }

    private struct RejectingApproval: JWAApprovalUI {
        func requestApproval(_ request: JWAIncomingRequest) async -> JWAApprovalDecision { .reject }
    }

    private final class RecordingApproval: JWAApprovalUI, @unchecked Sendable {
        var lastRequest: JWAIncomingRequest?
        func requestApproval(_ request: JWAIncomingRequest) async -> JWAApprovalDecision {
            lastRequest = request
            return .approve
        }
    }

    private final class CapturingReturnOpener: JWAReturnOpening, @unchecked Sendable {
        private(set) var lastURL: URL?
        @MainActor func open(_ url: URL) async -> Bool {
            lastURL = url
            return true
        }
    }

    private let redirect = URL(string: "agentic://wallet/return")!
    private let appURL = URL(string: "https://agentic.example")!

    private func connectRequest(_ dappKeypair: EphemeralKeypair) -> ConnectRequest {
        ConnectRequest(
            dappEncryptionPublicKey: Base58.encode(dappKeypair.publicKey),
            redirectLink: redirect,
            appURL: appURL,
            cluster: .mainnetBeta
        )
    }

    /// Connects against the handler and returns the established dApp-side session.
    private func connect(
        adapter: JupiterAdapter,
        handler: JupiterWalletHandler,
        opener: CapturingReturnOpener,
        dappKeypair: EphemeralKeypair
    ) async throws -> Session {
        let connectURL = try adapter.connectURL(request: connectRequest(dappKeypair))
        XCTAssertEqual(connectURL.scheme, "jupiter")
        XCTAssertTrue(connectURL.absoluteString.hasPrefix("jupiter://v1/connect?"), connectURL.absoluteString)

        let handled = await handler.handleIncomingURL(connectURL)
        XCTAssertTrue(handled)

        let callback = try XCTUnwrap(opener.lastURL)
        // Auto-return: the wallet bounced the user back to the dApp's redirect target.
        XCTAssertEqual(callback.scheme, "agentic")
        XCTAssertEqual(callback.host, "wallet")
        return try WalletResponseDecoder.connectSession(from: callback, keypair: dappKeypair)
    }

    // MARK: - Transport shape

    func testCustomSchemeTransportShape() throws {
        let host = DeeplinkURL.WalletHost(universalLinkHost: "", customScheme: "jupiter")
        let url = try DeeplinkURL.make(host: host, method: "signMessage", transport: .customScheme, params: [("k", "v")])
        XCTAssertEqual(url.scheme, "jupiter")
        XCTAssertTrue(url.absoluteString.hasPrefix("jupiter://v1/signMessage?"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("k=v"))
    }

    func testUniversalLinkTransportUnchanged() throws {
        let host = DeeplinkURL.WalletHost(universalLinkHost: "phantom.app", customScheme: "phantom")
        let url = try DeeplinkURL.make(host: host, method: "connect", params: [("k", "v")])
        XCTAssertEqual(url.absoluteString, "https://phantom.app/ul/v1/connect?k=v")
    }

    // MARK: - Round trips

    func testConnectRoundTripEstablishesSession() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()

        let session = try await connect(adapter: JupiterAdapter(), handler: handler, opener: opener, dappKeypair: dappKeypair)
        XCTAssertEqual(session.userPublicKey, signer.userPublicKey)
        XCTAssertEqual(session.walletEncryptionPublicKey.count, NaClBox.keyLength)
    }

    func testSignMessageRoundTrip() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        let session = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: dappKeypair)

        let url = try adapter.signMessageURL(message: Data("gm".utf8), session: session, keypair: dappKeypair, redirectLink: redirect)
        XCTAssertTrue(url.absoluteString.hasPrefix("jupiter://v1/signMessage?"), url.absoluteString)
        _ = await handler.handleIncomingURL(url)

        let callback = try XCTUnwrap(opener.lastURL)
        let result = try WalletResponseDecoder.signMessageResult(from: callback, session: session, keypair: dappKeypair)
        XCTAssertEqual(result.signature, signer.messageSignature)
    }

    func testSignTransactionRoundTrip() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        let session = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: dappKeypair)

        let url = try adapter.signTransactionURL(transaction: Data("txbytes".utf8), session: session, keypair: dappKeypair, redirectLink: redirect)
        _ = await handler.handleIncomingURL(url)

        let callback = try XCTUnwrap(opener.lastURL)
        let result = try WalletResponseDecoder.signTransactionResult(from: callback, session: session, keypair: dappKeypair)
        XCTAssertEqual(result.transaction, signer.signedTransaction)
    }

    func testSignAllTransactionsRoundTrip() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        let session = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: dappKeypair)

        let url = try adapter.signAllTransactionsURL(transactions: [Data("a".utf8), Data("b".utf8)], session: session, keypair: dappKeypair, redirectLink: redirect)
        _ = await handler.handleIncomingURL(url)

        let callback = try XCTUnwrap(opener.lastURL)
        let result = try WalletResponseDecoder.signAllTransactionsResult(from: callback, session: session, keypair: dappKeypair)
        XCTAssertEqual(result.transactions, [signer.signedTransaction, signer.signedTransaction])
    }

    func testSignAndSendTransactionRoundTrip() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        let session = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: dappKeypair)

        let url = try adapter.signAndSendTransactionURL(transaction: Data("txbytes".utf8), session: session, keypair: dappKeypair, redirectLink: redirect)
        _ = await handler.handleIncomingURL(url)

        let callback = try XCTUnwrap(opener.lastURL)
        let result = try WalletResponseDecoder.signAndSendTransactionResult(from: callback, session: session, keypair: dappKeypair)
        XCTAssertEqual(result.signature, signer.txid)
    }

    // MARK: - Error paths

    func testConnectRejectionSurfacesUserRejected() async throws {
        let opener = CapturingReturnOpener()
        let handler = JupiterWalletHandler(signer: TestSigner(), approvalUI: RejectingApproval(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()

        _ = await handler.handleIncomingURL(try JupiterAdapter().connectURL(request: connectRequest(dappKeypair)))
        let callback = try XCTUnwrap(opener.lastURL)
        let error = WalletResponseDecoder.error(from: callback)
        guard case .userRejected = try XCTUnwrap(error) else {
            return XCTFail("Expected userRejected, got \(String(describing: error))")
        }
    }

    func testSigningWithoutSessionSurfacesInvalidSession() async throws {
        let opener = CapturingReturnOpener()
        let handler = JupiterWalletHandler(signer: TestSigner(), approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        // A session the handler never issued.
        let strangerSession = Session(
            walletEncryptionPublicKey: EphemeralKeypair.generate().publicKey,
            token: "never-issued",
            userPublicKey: "stranger"
        )

        let url = try JupiterAdapter().signMessageURL(message: Data("hi".utf8), session: strangerSession, keypair: dappKeypair, redirectLink: redirect)
        _ = await handler.handleIncomingURL(url)
        let callback = try XCTUnwrap(opener.lastURL)
        let error = WalletResponseDecoder.error(from: callback)
        guard case .invalidSession = try XCTUnwrap(error) else {
            return XCTFail("Expected invalidSession, got \(String(describing: error))")
        }
    }

    func testNonJWAURLIsNotConsumed() async throws {
        let opener = CapturingReturnOpener()
        let handler = JupiterWalletHandler(signer: TestSigner(), approvalUI: JWAAlwaysApprove(), returnOpener: opener)
        // No redirect_link / unknown method → not a jWA request.
        let handled = await handler.handleIncomingURL(URL(string: "jupiter://v1/swap?token=SOL")!)
        XCTAssertFalse(handled)
        XCTAssertNil(opener.lastURL)
    }

    // MARK: - Polish coverage

    func testApprovalReceivesDecodedSigningContent() async throws {
        let approval = RecordingApproval()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: TestSigner(), approvalUI: approval, returnOpener: opener)
        let dappKeypair = EphemeralKeypair.generate()
        let session = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: dappKeypair)

        let message = Data("approve this exact message".utf8)
        _ = await handler.handleIncomingURL(try adapter.signMessageURL(message: message, session: session, keypair: dappKeypair, redirectLink: redirect))

        guard case .message(let captured)? = approval.lastRequest?.signingRequest else {
            return XCTFail("Approval did not receive a .message signing request; got \(String(describing: approval.lastRequest?.signingRequest))")
        }
        XCTAssertEqual(captured, message, "Wallet approval must see the exact bytes being signed")
    }

    func testMultipleDappSessionsAreIsolated() async throws {
        let signer = TestSigner()
        let opener = CapturingReturnOpener()
        let adapter = JupiterAdapter()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: JWAAlwaysApprove(), returnOpener: opener)

        let keypairA = EphemeralKeypair.generate()
        let keypairB = EphemeralKeypair.generate()
        let sessionA = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: keypairA)
        let sessionB = try await connect(adapter: adapter, handler: handler, opener: opener, dappKeypair: keypairB)
        XCTAssertNotEqual(sessionA.walletEncryptionPublicKey, sessionB.walletEncryptionPublicKey)

        _ = await handler.handleIncomingURL(try adapter.signMessageURL(message: Data("a".utf8), session: sessionA, keypair: keypairA, redirectLink: redirect))
        let resultA = try WalletResponseDecoder.signMessageResult(from: try XCTUnwrap(opener.lastURL), session: sessionA, keypair: keypairA)
        XCTAssertEqual(resultA.signature, signer.messageSignature)

        _ = await handler.handleIncomingURL(try adapter.signMessageURL(message: Data("b".utf8), session: sessionB, keypair: keypairB, redirectLink: redirect))
        let resultB = try WalletResponseDecoder.signMessageResult(from: try XCTUnwrap(opener.lastURL), session: sessionB, keypair: keypairB)
        XCTAssertEqual(resultB.signature, signer.messageSignature)
    }

    func testSessionStoreEvictsOldestPastCap() {
        let store = InMemoryJWASessionStore(maxSessions: 2)
        let k1 = EphemeralKeypair.generate()
        let k2 = EphemeralKeypair.generate()
        let k3 = EphemeralKeypair.generate()
        func make(_ keypair: EphemeralKeypair, _ token: String) -> JWAStoredSession {
            JWAStoredSession(dappEncryptionPublicKey: keypair.publicKey, walletKeypair: .generate(), token: token, userPublicKey: "u")
        }
        store.store(make(k1, "t1"))
        store.store(make(k2, "t2"))
        store.store(make(k3, "t3"))
        XCTAssertNil(store.session(forDappKey: k1.publicKey), "Oldest session should be evicted past the cap")
        XCTAssertNotNil(store.session(forDappKey: k2.publicKey))
        XCTAssertNotNil(store.session(forDappKey: k3.publicKey))
    }
}
