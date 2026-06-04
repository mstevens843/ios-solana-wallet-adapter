import Foundation
import SolanaWalletAdapter

/// Broadcasts an already-signed Solana transaction through a JSON-RPC endpoint.
///
/// Used by `WalletAdapterClient.signAndSendViaRPC(_:rpcURL:sendOptions:)` to
/// implement "sign-then-send" for wallets whose native `signAndSendTransaction`
/// is deprecated or unavailable (e.g. Phantom). The wallet signs locally; this
/// type submits the raw signed bytes to the caller's RPC (Helius, Triton, the
/// public endpoint, …). HTTP/error handling mirrors the demo's
/// `DemoTransactionBuilder.fetchLatestBlockhash`.
public struct SolanaRPCSender: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Submit a signed transaction via JSON-RPC `sendTransaction`.
    ///
    /// - Parameters:
    ///   - signedTransaction: The signed wire-format bytes, i.e. the `Data` from
    ///     `SignTransactionResult.transaction`. Base64-encoded directly (do not
    ///     base58-decode) because the request uses `{ "encoding": "base64" }`.
    ///   - rpcURL: The JSON-RPC endpoint.
    ///   - sendOptions: Maps to the `sendTransaction` config object.
    /// - Returns: The transaction signature (txid) from the RPC `result`.
    /// - Throws: `WalletAdapterError.other(code: "rpc_send_failed", message:)` on
    ///   any network, HTTP, decoding, or RPC error (the RPC `error.message` is
    ///   surfaced verbatim so callers can show it).
    public func sendTransaction(
        _ signedTransaction: Data,
        rpcURL: URL,
        sendOptions: SendOptions = .init()
    ) async throws -> String {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var rpcOptions: [String: Any] = [
            "encoding": "base64",
            "skipPreflight": sendOptions.skipPreflight,
        ]
        if let commitment = sendOptions.preflightCommitment {
            rpcOptions["preflightCommitment"] = commitment
        }
        if let maxRetries = sendOptions.maxRetries {
            rpcOptions["maxRetries"] = maxRetries
        }
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [signedTransaction.base64EncodedString(), rpcOptions],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WalletAdapterError.other(
                code: "rpc_send_failed",
                message: "Network error broadcasting transaction: \(error.localizedDescription)"
            )
        }

        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw WalletAdapterError.other(code: "rpc_send_failed", message: "RPC returned HTTP \(status).")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WalletAdapterError.other(code: "rpc_send_failed", message: "RPC response was not valid JSON.")
        }
        if let rpcError = json["error"] as? [String: Any], let message = rpcError["message"] as? String {
            throw WalletAdapterError.other(code: "rpc_send_failed", message: message)
        }
        guard let txid = json["result"] as? String else {
            throw WalletAdapterError.other(code: "rpc_send_failed", message: "RPC response missing result txid.")
        }
        return txid
    }
}
