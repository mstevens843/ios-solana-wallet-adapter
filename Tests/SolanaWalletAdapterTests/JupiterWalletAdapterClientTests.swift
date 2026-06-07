import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterJupiter
import SolanaWalletAdapterJupiterHandler
import SolanaWalletAdapterUI

/// Exercises the jWA path through the REAL app-facing `WalletAdapterClient` (not
/// just the provider+handler+decoder directly): the client's opener loops every
/// opened wallet URL through a `JupiterWalletHandler` and feeds the fired callback
/// back into `client.handleOpenURL`, proving `matchesRedirectLink`/`handleOpenURL`/
/// disconnect work for the custom-scheme transport end-to-end.
@MainActor
final class JupiterWalletAdapterClientTests: XCTestCase {

    private struct LoopSigner: JWASigner {
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

    private final class CapturingReturnOpener: JWAReturnOpening, @unchecked Sendable {
        var lastURL: URL?
        @MainActor func open(_ url: URL) async -> Bool { lastURL = url; return true }
    }

    private final class ClientBox: @unchecked Sendable {
        weak var client: WalletAdapterClient?
    }

    private let appURL = URL(string: "https://agentic.example")!
    private let redirect = URL(string: "agentic://wallet/return")!

    /// Build a client whose opener loops opened URLs through a real handler and
    /// feeds the fired callback back into the client — the true consumer path.
    private func makeClient(
        signer: JWASigner = LoopSigner(),
        approval: JWAApprovalUI = JWAAlwaysApprove()
    ) -> WalletAdapterClient {
        let box = ClientBox()
        let handlerOpener = CapturingReturnOpener()
        let handler = JupiterWalletHandler(signer: signer, approvalUI: approval, returnOpener: handlerOpener)
        let opener = ClosureWalletURLOpener { url in
            _ = await handler.handleIncomingURL(url)
            if let callback = handlerOpener.lastURL {
                handlerOpener.lastURL = nil
                _ = box.client?.handleOpenURL(callback)
            }
            return true
        }
        let client = WalletAdapterClient(provider: JupiterAdapter(), appURL: appURL, redirectLink: redirect, opener: opener)
        box.client = client
        return client
    }

    func testConnectThroughClient() async throws {
        let session = try await makeClient().connect()
        XCTAssertEqual(session.userPublicKey, LoopSigner().userPublicKey)
    }

    func testSignMessageThroughClient() async throws {
        let client = makeClient()
        _ = try await client.connect()
        let result = try await client.signMessage(Data("gm".utf8))
        XCTAssertEqual(result.signature, LoopSigner().messageSignature)
    }

    func testSignTransactionThroughClient() async throws {
        let client = makeClient()
        _ = try await client.connect()
        let result = try await client.signTransaction(Data("txbytes".utf8))
        XCTAssertEqual(result.transaction, LoopSigner().signedTransaction)
    }

    func testSignAllTransactionsThroughClient() async throws {
        let client = makeClient()
        _ = try await client.connect()
        let result = try await client.signAllTransactions([Data("a".utf8), Data("b".utf8)])
        XCTAssertEqual(result.transactions, [LoopSigner().signedTransaction, LoopSigner().signedTransaction])
    }

    func testSignAndSendThroughClient() async throws {
        let client = makeClient()
        _ = try await client.connect()
        let result = try await client.signAndSendTransaction(Data("txbytes".utf8))
        XCTAssertEqual(result.signature, LoopSigner().txid)
    }

    func testDisconnectThroughClient() async throws {
        let client = makeClient()
        _ = try await client.connect()
        // Bare-redirect ack from the handler; must complete without throwing.
        try await client.disconnect()
    }

    func testConnectRejectionThroughClientSurfacesUserRejected() async throws {
        let client = makeClient(approval: RejectingApproval())
        do {
            _ = try await client.connect()
            XCTFail("Expected userRejected")
        } catch let error as WalletAdapterError {
            guard case .userRejected = error else {
                return XCTFail("Expected userRejected, got \(error)")
            }
        }
    }

    // MARK: - Registry reconciliation (B)

    func testRegistryResolvesJupiterAsPreviewProvider() {
        XCTAssertTrue(WalletProviderRegistry.provider(for: "jupiter") is JupiterAdapter,
                      "Selecting Jupiter must resolve (no dead-end)")
        XCTAssertFalse(WalletProviderRegistry.supportedProviders.contains { $0.walletId == "jupiter" },
                       "Jupiter must stay out of the verified supportedProviders (gate intact)")
        XCTAssertTrue(WalletProviderRegistry.previewProviders.contains { $0.walletId == "jupiter" },
                      "Jupiter is an opt-in preview provider")
    }
}
