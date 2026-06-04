import XCTest
import SolanaWalletAdapter

final class WalletAdapterErrorUserMessageTests: XCTestCase {
    /// Every case must map to a non-empty, deterministic, user-facing string so
    /// the demo's fail toast is never a raw `Error` dump.
    func testEveryCaseHasNonEmptyDeterministicMessage() {
        let cases: [WalletAdapterError] = [
            .userRejected,
            .invalidSession,
            .unsupportedMethod("signAndSendTransaction"),
            .malformedPayload("bad"),
            .walletUnreachable,
            .decryptionFailed,
            .clusterMismatch(expected: .mainnetBeta, got: "devnet"),
            .operationInProgress,
            .noPendingRequest,
            .requestCancelled,
            .other(code: "rpc_send_failed", message: "blockhash not found"),
        ]
        for error in cases {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error) produced an empty userMessage")
        }
    }

    func testSpecificMappings() {
        XCTAssertEqual(WalletAdapterError.userRejected.userMessage, "Rejected in wallet")
        XCTAssertEqual(WalletAdapterError.invalidSession.userMessage, "Session expired — reconnect")
        XCTAssertEqual(WalletAdapterError.unsupportedMethod("x").userMessage, "Not supported by this wallet")
        XCTAssertEqual(WalletAdapterError.walletUnreachable.userMessage, "Couldn't reach wallet")
    }

    /// `.other` surfaces the wallet/RPC-supplied message verbatim so callers see
    /// the real reason (e.g. an RPC error string).
    func testOtherSurfacesUnderlyingMessage() {
        XCTAssertEqual(
            WalletAdapterError.other(code: "rpc_send_failed", message: "Transaction simulation failed").userMessage,
            "Transaction simulation failed"
        )
    }
}
